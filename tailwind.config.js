/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: '#004700',
          50: '#e6f0e6',
          100: '#cce2cc',
          200: '#99c599',
          300: '#66a866',
          400: '#338b33',
          500: '#004700', // Deep Forest Green
          600: '#003a00',
          700: '#002c00',
          800: '#001f00',
          900: '#001300',
          950: '#000a00',
        },
        'forest-green': '#004700',
      },
    },
  },
  plugins: [],
};