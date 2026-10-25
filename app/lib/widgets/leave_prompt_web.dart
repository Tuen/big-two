import "dart:js_interop";
import "dart:js_interop_unsafe";

/// The page script in web/index.html reads this and shows the browser prompt.
void setPageLeavePrompt(bool armed) {
  globalContext.setProperty("bigTwoArmLeavePrompt".toJS, armed.toJS);
}
