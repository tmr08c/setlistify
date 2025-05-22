// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/*_web.ex",
    "../lib/*_web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
      },
      fontFamily: {
        'sans': ['-apple-system', 'BlinkMacSystemFont', '"Segoe UI"', 'Roboto', 'Helvetica', 'Arial', 'sans-serif'],
      },
      animation: {
        'fade-slide': 'fadeSlide 1s ease-out',
        'bounce': 'bounce 1.5s ease-in-out infinite',
        'bounce-delayed': 'bounceDelayed 2s ease-in-out infinite',
      },
      keyframes: {
        fadeSlide: {
          '0%': { opacity: '0', transform: 'translateY(10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        bounceDelayed: {
          '0%, 20%': { transform: 'translateY(0)' },
          '30%': { transform: 'translateY(-20px)' },
          '40%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
          '60%': { transform: 'translateY(0)' },
          '100%': { transform: 'translateY(0)' },
        },
      },
    },
  },
  plugins: [
    // Note: @tailwindcss/forms may not be compatible with v4 yet
    // require("@tailwindcss/forms"),
    plugin(({addVariant}) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"]))
  ]
}
