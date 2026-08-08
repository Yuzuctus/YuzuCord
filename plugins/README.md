# Sources des plugins Yuzuctus

Chaque sous-dossier contient un plugin Vencord indépendant dont le nom de dossier correspond à son `id` dans
`catalog/plugins.json`.

Un plugin doit posséder son propre `index.tsx`, ses réglages, ses patchs Discord et ses tests métier. Le code
réutilisable par plusieurs plugins appartient à `shared/` et est ajouté au résultat final par les `mappings` du
catalogue. Un plugin ne doit pas importer directement le dossier source d’un autre plugin.

Pour ajouter un plugin :

1. créer `plugins/<pluginId>/index.tsx` ;
2. ajouter les tests à côté du code pur ;
3. ajouter une entrée complète dans `catalog/plugins.json` ;
4. déclarer les bibliothèques partagées dans `mappings` ;
5. lancer `scripts/Test-PluginCatalog.ps1`, puis les tests, le lint, le typecheck et le build Vencord.

La provenance est déclarée dans le catalogue et ne doit pas être recopiée dans le code du plugin. Le wrapper
généré ajoute `YuzuMod` pour une création Yuzuctus ou `ThirdParty` pour une intégration externe.

Les chaînes visibles dans Discord doivent utiliser une localisation français/anglais lorsque c’est pratique.
Les plugins ne doivent ajouter ni télémétrie, ni requête vers un service tiers, ni envoi sans action explicite.
