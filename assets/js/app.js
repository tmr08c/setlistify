// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

document.addEventListener("click", async (e) => {
  const btn = e.target.closest("[data-apple-music-signin]")
  if (!btn) return
  e.preventDefault()

  const originalHTML = btn.innerHTML
  btn.disabled = true
  btn.innerHTML = btn.innerHTML.replace(/Apple Music/, "Connecting\u2026")

  try {
    const music = await MusicKit.configure({
      developerToken: btn.dataset.developerToken,
      app: { name: "Setlistify", build: "1.0" }
    })
    const userToken = await music.authorize()
    const storefront = music.storefrontId

    const form = document.createElement("form")
    form.method = "POST"
    form.action = "/oauth/callbacks/apple_music"

    for (const [name, value] of Object.entries({
      _csrf_token: csrfToken,
      user_token: userToken,
      storefront: storefront,
      redirect_to: btn.dataset.redirectTo || "/"
    })) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.appendChild(input)
    }

    document.body.appendChild(form)
    form.submit()
  } catch (_error) {
    btn.disabled = false
    btn.innerHTML = originalHTML
  }
})

Hooks.RotatingText = {
  mounted() {
    this.texts = JSON.parse(this.el.dataset.texts)
    this.currentIndex = 0
    this.textElement = this.el.querySelector("span")

    setInterval(() => {
      this.currentIndex = (this.currentIndex + 1) % this.texts.length
      this.textElement.style.opacity = "0"

      setTimeout(() => {
        this.textElement.textContent = this.texts[this.currentIndex]
        this.textElement.style.opacity = "1"
      }, 350)
    }, 2000)
  }
}

Hooks.DelayedShow = {
  mounted() {
    const delay = parseInt(this.el.dataset.delay) || 300

    // Show after delay by removing opacity-0 class and adding opacity-100
    this.timeout = setTimeout(() => {
      this.isHidden = false
      this.el.classList.remove('opacity-0')
      this.el.classList.add('opacity-100')
    }, delay)
  },

  destroyed() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
}

let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", info => topbar.delayedShow(200))
window.addEventListener("phx:page-loading-stop", info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
