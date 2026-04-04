const AppleMusicAuth = {
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
          app: { name: "Setlistify", build: "1.0" }
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

export default AppleMusicAuth
