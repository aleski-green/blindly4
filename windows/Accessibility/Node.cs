using System.Windows.Automation;

namespace Blindly;

internal sealed class Node(AutomationElement? element, int pid)
{
    internal AutomationElement? Element { get; } = element;
    internal int Pid { get; } = pid;
    internal bool Root => Element == null;
    internal T? Pattern<T>(AutomationPattern pattern) where T : class => Element != null && Element.TryGetCurrentPattern(pattern, out object result) ? result as T : null;
    internal string Role
    {
        get
        {
            if (Root) return "AXApplication";
            var type = Element!.Current.ControlType;
            if (type == ControlType.Edit) return Element.Current.IsPassword ? "AXSecureTextField" : "AXTextField";
            if (type == ControlType.Document) return "AXTextArea";
            return type.ProgrammaticName.Split('.').Last() switch {
                "Window" => "AXWindow", "Button" => "AXButton", "Text" => "AXStaticText", "Hyperlink" => "AXLink",
                "CheckBox" => "AXCheckBox", "RadioButton" => "AXRadioButton", "ComboBox" => "AXComboBox",
                "Tab" => "AXTabGroup", "TabItem" => "AXRadioButton", "List" => "AXList", "ListItem" => "AXRow",
                "Tree" => "AXOutline", "TreeItem" => "AXRow", "Menu" => "AXMenu", "MenuBar" => "AXMenuBar",
                "MenuItem" => "AXMenuItem", "ScrollBar" => "AXScrollBar", "Slider" => "AXSlider", "Image" => "AXImage",
                "Table" or "DataGrid" => "AXTable", "ProgressBar" => "AXProgressIndicator", _ => "AXGroup"
            };
        }
    }
    internal string? Value
    {
        get
        {
            if (Root || Element!.Current.IsPassword) return null;
            var value = Pattern<ValuePattern>(ValuePattern.Pattern);
            if (value != null) return value.Current.Value;
            var text = Pattern<TextPattern>(TextPattern.Pattern);
            return text?.DocumentRange.GetText(65536);
        }
    }
    internal bool Writable => !Root && !Element!.Current.IsPassword && Element.Current.IsEnabled &&
        new[] { "AXTextField", "AXTextArea", "AXComboBox" }.Contains(Role) &&
        Pattern<ValuePattern>(ValuePattern.Pattern) is { Current.IsReadOnly: false };
    internal bool HasFocus => Element != null && Element.Current.HasKeyboardFocus && Automation.Compare(Element, AutomationElement.FocusedElement);
    internal bool ExactDraft(string expected) => !Root && Value is string value && Guards.Exact(value, expected);
    internal bool Selected => Pattern<SelectionItemPattern>(SelectionItemPattern.Pattern)?.Current.IsSelected == true;
    internal string[] Actions()
    {
        var actions = new List<string>();
        if (Pattern<InvokePattern>(InvokePattern.Pattern) != null || Pattern<SelectionItemPattern>(SelectionItemPattern.Pattern) != null || Pattern<TogglePattern>(TogglePattern.Pattern) != null) actions.Add("AXPress");
        if (Pattern<ExpandCollapsePattern>(ExpandCollapsePattern.Pattern) != null) actions.Add("AXShowMenu");
        if (Pattern<ScrollItemPattern>(ScrollItemPattern.Pattern) != null) actions.Add("AXScrollToVisible");
        return actions.ToArray();
    }
    internal Dictionary<string, object?> Detail(string? path = null)
    {
        var row = new Dictionary<string, object?> { ["pid"] = Pid, ["role"] = Role };
        if (path != null) row["path"] = path;
        if (Root) { row["title"] = Native.ProcessName(Pid); return row; }
        var current = Element!.Current;
        row["title"] = current.Name;
        row["description"] = string.IsNullOrEmpty(current.HelpText) ? current.Name : current.HelpText;
        row["identifier"] = current.AutomationId;
        row["subrole"] = current.ControlType.ProgrammaticName;
        row["value"] = Value;
        row["enabled"] = current.IsEnabled;
        row["focused"] = current.HasKeyboardFocus;
        row["selected"] = Selected;
        row["actions"] = Actions();
        row["attributes"] = new[] { "AXRole", "AXTitle", "AXDescription", "AXValue", "AXEnabled", "AXFocused", "AXSelected", "AXPosition", "AXSize" };
        var bounds = current.BoundingRectangle;
        if (!bounds.IsEmpty && double.IsFinite(bounds.X) && double.IsFinite(bounds.Y))
        {
            row["position"] = new { x = bounds.X, y = bounds.Y };
            row["size"] = new { width = bounds.Width, height = bounds.Height };
        }
        return row;
    }
    internal IEnumerable<Node> Children()
    {
        if (Root)
        {
            foreach (var window in Native.Windows().Where(w => w.Pid == Pid)) yield return new Node(AutomationElement.FromHandle(window.Handle), Pid);
            yield break;
        }
        var walker = TreeWalker.ControlViewWalker;
        var child = walker.GetFirstChild(Element);
        int count = 0;
        while (child != null)
        {
            if (++count > 10000) throw CliError.Access("Control has more than 10000 children; narrow the target");
            yield return new Node(child, Pid);
            child = walker.GetNextSibling(child);
        }
    }
    internal void Focus()
    {
        if (Root) throw new CliError("Choose a control path");
        Native.Activate(Pid);
        Element!.SetFocus();
        if (!HasFocus) throw CliError.Access("The target did not receive keyboard focus");
    }
    internal void SetValue(string text)
    {
        if (!Writable) throw new CliError("Target is not a writable UI Automation text control");
        Pattern<ValuePattern>(ValuePattern.Pattern)!.SetValue(text);
    }
    internal void Press()
    {
        if (Pattern<InvokePattern>(InvokePattern.Pattern) is { } invoke) invoke.Invoke();
        else if (Pattern<SelectionItemPattern>(SelectionItemPattern.Pattern) is { } select) select.Select();
        else if (Pattern<TogglePattern>(TogglePattern.Pattern) is { } toggle) toggle.Toggle();
        else throw new CliError("Target does not support AXPress");
    }
    internal void Expand()
    {
        if (Pattern<ExpandCollapsePattern>(ExpandCollapsePattern.Pattern) is not { } expand) throw new CliError("Target does not support AXShowMenu");
        expand.Expand();
    }
    internal void ScrollTo()
    {
        if (Pattern<ScrollItemPattern>(ScrollItemPattern.Pattern) is not { } scroll) throw new CliError("Target does not support AXScrollToVisible");
        scroll.ScrollIntoView();
    }
}
