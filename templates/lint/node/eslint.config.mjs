// agent-harness default ESLint config for new TypeScript projects.
import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import { defineConfig } from "eslint/config";
import tseslint from "typescript-eslint";

export default defineConfig(
  { ignores: ["dist/", "build/", "coverage/", ".next/", "node_modules/"] },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      // A lint-only tsconfig covers tests and *.config.ts that the build tsconfig leaves out.
      parserOptions: { project: "./tsconfig.eslint.json", tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/consistent-type-assertions": ["error", { assertionStyle: "never" }],
      "@typescript-eslint/no-non-null-assertion": "error",
      "max-depth": ["error", 3],
      "no-else-return": ["error", { allowElseIf: false }],
      "no-param-reassign": [
        "error",
        // Framework objects meant to be mutated (Express req/res, Koa ctx).
        { props: true, ignorePropertyModificationsFor: ["req", "res", "request", "response", "ctx"] },
      ],
      "prefer-const": "error",
    },
  },
  {
    files: ["**/*.{js,mjs,cjs}"],
    extends: [tseslint.configs.disableTypeChecked],
  },
  prettier,
);
