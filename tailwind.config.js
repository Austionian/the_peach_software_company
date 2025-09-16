/** @type {import('tailwindcss').Config} */
const colors = require("tailwindcss/colors");

module.exports = {
  content: ["./templates/**/*.{html,js}"],
  theme: {
    extend: {
      colors: {
        primary: "#ff6596",
        secondary: "#00e8ff",
        alt: "#ce74ff",
        altDark: "#111a3b",
        bg: "#fff",
        text: "pink",
      },
    },
  },
};
