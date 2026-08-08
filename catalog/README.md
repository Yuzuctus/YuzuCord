# Plugin catalog

`plugins.json` is the source of truth for the plugins included in the Yuzuctus Vencord distribution.

Each plugin is materialized into its own direct child of `src/userplugins` before Vencord is built. The
catalog currently contains only `randomFavorites`; its shape is ready for future plugins without changing
the build or installer architecture.

Plugin sources are copied from a local distribution checkout for now. A future community entry must provide
an exact source commit, a compatible license, and an explicit review before it is added to a beta release.
