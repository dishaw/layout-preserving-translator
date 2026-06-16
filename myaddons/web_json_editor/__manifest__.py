{
    "name": "Web JSON Editor",
    "version": "18.0.1.0.0",
    "category": "Web",
    "summary": "JSON Editor widget for Odoo",
    "description": """
        Provides a reusable JSON Editor widget for Odoo with schema-based autocomplete.
        Features:
        - JSON syntax highlighting
        - Schema-based autocomplete
        - Multiple view modes (code, tree, form, view)
        - Validation
    """,
    "depends": [
        "web",
    ],
    "assets": {
        "web.assets_backend": [
            # JSONEditor itself is loaded lazily by the widget, so normal Odoo
            # pages do not pay the 1MB download/parse cost on first load.
            "web_json_editor/static/src/lib/jsoneditor_loader.js",
            # Field widget
            "web_json_editor/static/src/fields/json_field.js",
            "web_json_editor/static/src/fields/json_field.xml",
            "web_json_editor/static/src/fields/json_field.scss",
            # OWL Component
            "web_json_editor/static/src/components/json_editor/json_editor.js",
            "web_json_editor/static/src/components/json_editor/json_editor.xml",
        ],
    },
    "author": "Apexive Solutions LLC",
    "website": "https://github.com/apexive/odoo-llm",
    "installable": True,
    "application": False,
    "auto_install": False,
    "license": "LGPL-3",
}
