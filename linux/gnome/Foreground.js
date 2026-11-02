const api = `<node><interface name="org.sapiens.Blindly.Foreground1">
<method name="Get"><arg name="pid" type="u" direction="out"/></method>
<method name="Point"><arg type="u" direction="in"/><arg type="d" direction="in"/><arg type="d" direction="in"/>
<arg type="b" direction="out"/><arg type="d" direction="out"/><arg type="d" direction="out"/></method>
<method name="Pointer"><arg type="u" direction="in"/><arg type="b" direction="out"/></method>
</interface></node>`;

class Foreground extends Extension {
    enable() {
        this._object = Gio.DBusExportedObject.wrapJSObject(api, this);
        this._object.export(Gio.DBus.session, '/org/sapiens/Blindly/Foreground');
    }

    Get() {
        if (Main.sessionMode.isLocked || Main.sessionMode.isGreeter ||
            Main.screenShield?.locked || Main.overview.visible || Main.modalCount > 0)
            return 0;
        const window = global.display.get_focus_window();
        if (!window || window.get_client_type() !== Meta.WindowClientType.WAYLAND ||
            !window.has_focus() || window.is_hidden())
            return 0;
        const pid = window.get_pid();
        return Number.isInteger(pid) && pid > 0 ? pid : 0;
    }

    disable() {
        this._object?.unexport();
        this._object = null;
    }

    _owns(pid, x, y) {
        if (!pid || this.Get() !== pid || !Number.isFinite(x) || !Number.isFinite(y))
            return false;
        const window = global.display.get_focus_window();
        const rect = window.get_buffer_rect();
        if (x < rect.x || y < rect.y || x >= rect.x + rect.width || y >= rect.y + rect.height)
            return false;
        let actor = global.stage.get_actor_at_pos(Clutter.PickMode.REACTIVE, x, y);
        for (let depth = 0; actor && depth < 32; depth++, actor = actor.get_parent()) {
            if (actor instanceof Meta.WindowActor)
                return actor.get_meta_window() === window;
        }
        return false;
    }

    Point(pid, x, y) {
        if (!this._owns(pid, x, y)) return [false, 0, 0];
        const [currentX, currentY] = global.get_pointer();
        return [true, x - currentX, y - currentY];
    }

    Pointer(pid) {
        const [x, y] = global.get_pointer();
        return this._owns(pid, x, y);
    }
}
