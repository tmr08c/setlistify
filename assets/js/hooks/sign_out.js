const SignOut = {
  mounted() {
    this.el.addEventListener("click", () => {
      MusicKit.getInstance?.()?.unauthorize?.()
    })
  }
}

export default SignOut
