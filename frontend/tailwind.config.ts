import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        axis: {
          50: "#f3f7fc",
          100: "#e3ecf8",
          200: "#cbdcf0",
          300: "#a7c3e4",
          400: "#7ca3d4",
          500: "#5d84c5",
          600: "#4569b5",
          700: "#34549f",
          800: "#164a9e",
          900: "#0b3c74",
          950: "#07284e"
        }
      },
      boxShadow: {
        card: "0 18px 50px rgba(11, 60, 116, 0.10)"
      }
    }
  },
  plugins: []
};

export default config;

