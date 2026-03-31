const AppleMusicAuth = {
  mounted() {
    this.handleEvent("request_apple_music_auth", async ({ developer_token }) => {
      try {
        const music = await MusicKit.configure({
          developerToken: developer_token,
          app: { name: "Setlistify", build: "1.0" }
        })

        const userToken = await music.authorize()
        const storefront = music.storefrontId

        this.pushEvent("apple_music_authorized", { user_token: userToken, storefront })
      } catch (error) {
        this.pushEvent("apple_music_auth_failed", { reason: error.message })
      }
    })
  }
}

export default AppleMusicAuth
