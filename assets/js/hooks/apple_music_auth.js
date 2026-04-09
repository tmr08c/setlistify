// MusicKit.configure() app options affect the authorization dialog UI.
// - app.name: Passed to MusicKit, but Apple's auth dialog always shows the
//   requesting domain (e.g. "setlistify.fly.dev would like to access...") as a
//   security transparency feature — app.name does not override this.
// - app.icon: A URL to the icon shown in the auth dialog. This does take effect
//   (the favicon is visible in the dialog).
const MUSICKIT_APP_CONFIG = {
  name: "Setlistify",
  build: "1.0",
  icon: `${window.location.origin}/favicon.ico`
}

export const AppleMusicAuth = {
  mounted() {
    this.el.addEventListener("click", async (e) => {
      e.preventDefault()

      const btn = this.el
      const originalHTML = btn.innerHTML
      btn.disabled = true
      btn.innerHTML = btn.innerHTML.replace(/Apple Music/, "Connecting\u2026")

      try {
        const music = await MusicKit.configure({
          developerToken: btn.dataset.developerToken,
          app: MUSICKIT_APP_CONFIG
        })
        const userToken = await music.authorize()
        const storefront = music.storefrontId
        this.pushEvent("apple_music_authorized", { user_token: userToken, storefront })
      } catch (error) {
        btn.disabled = false
        btn.innerHTML = originalHTML
        this.pushEvent("apple_music_auth_failed", { reason: error.message || "Unknown error" })
      }
    })
  }
}

export const AppleMusicSignOut = {
  mounted() {
    this.el.addEventListener("click", async (e) => {
      e.preventDefault()
      try {
        const music = await MusicKit.configure({
          developerToken: this.el.dataset.developerToken,
          app: MUSICKIT_APP_CONFIG
        })
        await music.unauthorize()
      } catch (_) {
        // best effort — proceed with sign-out regardless
      }
      window.location = "/signout"
    })
  }
}
