import js from "@eslint/js";
import importPlugin from "eslint-plugin-import";
import security from "eslint-plugin-security";
import prettierConfig from "eslint-config-prettier";

/** @type {import('eslint').Linter.Config[]} */
export default [
  js.configs.recommended,
  security.configs.recommended,
  prettierConfig,
  {
    plugins: {
      import: importPlugin,
    },
    rules: {
      // Import organization
      "import/order": [
        "warn",
        {
          groups: ["builtin", "external", "internal", "parent", "sibling", "index"],
          "newlines-between": "always",
        },
      ],
      "import/no-duplicates": "error",

      // Code quality
      "no-unused-vars": ["warn", { argsIgnorePattern: "^_" }],
      "no-console": "warn",
      "prefer-const": "error",
      "no-var": "error",
      eqeqeq: ["error", "always"],
    },
  },
  {
    ignores: ["node_modules/", "dist/", "build/", "coverage/", ".next/"],
  },
];
