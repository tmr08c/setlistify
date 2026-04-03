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
        const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

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
  }
}

export default AppleMusicAuth
