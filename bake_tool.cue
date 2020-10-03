package bake

command: {
  image: #Dubo & {
    args: {
      BUILD_TITLE: "Buildkit"
      BUILD_DESCRIPTION: "A dubo image for Buildkit based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }

    platforms: [
      AMD64
    ]
  }
}
