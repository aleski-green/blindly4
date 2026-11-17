import Lake
open Lake DSL
package «blindly-behavior»
lean_lib Tests
@[test_driver, default_target]
lean_exe behavior where
  root := `Main
