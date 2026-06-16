/** @odoo-module */

import { loadCSS, loadJS } from "@web/core/assets";

let jsonEditorPromise;

export async function loadJsonEditor() {
  if (window.JSONEditor) {
    return window.JSONEditor;
  }

  if (!jsonEditorPromise) {
    jsonEditorPromise = Promise.all([
      loadCSS("/web_json_editor/static/lib/jsoneditor/jsoneditor.min.css"),
      loadJS("/web_json_editor/static/lib/jsoneditor/jsoneditor.min.js"),
    ]).then(() => {
      if (!window.JSONEditor) {
        throw new Error("JSONEditor failed to load");
      }
      return window.JSONEditor;
    });
  }

  return jsonEditorPromise;
}
