# Developing

Assuming you have opam-publish in a switch called `opam-publish` you can create a PR
to diskuv-opam-repository with the following:

```
opam exec --switch opam-publish -- opam-publish --repo diskuv/diskuv-opam-repository -v 1.0.2~prerel0 -b main
```

Change the version number!
