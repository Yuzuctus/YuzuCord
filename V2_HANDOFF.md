# V2 Handoff - Yuzuctus Vencord

Ce document est la reference de reprise pour une autre IA ou un autre developpeur. Il decrit l'etat du depot
apres la migration de l'ancien projet RandomFavorites vers une distribution Vencord modulaire.

## Objectif du projet

Le projet ne doit plus etre presente comme un simple installateur de RandomFavorites. Le produit est maintenant
**Yuzuctus Vencord** : une distribution Windows de Vencord construite par Yuzuctus.

Objectifs definis :

- fournir un installateur Windows pour une build Vencord personnalisee ;
- integrer plusieurs plugins Vencord dans une meme build ;
- permettre plus tard d'ajouter des plugins crees par Yuzuctus ou par d'autres utilisateurs ;
- garder RandomFavorites comme plugin actuel, sans ajouter de nouveau plugin pour le moment ;
- publier uniquement en beta pendant la phase V2 ;
- conserver une architecture qui ne necessite pas de reecrire l'installateur lorsqu'un plugin est ajoute.

## Etat Git actuel

Depot distant : `https://github.com/Yuzuctus/RandomFavorites.git`

Etat actuel :

- branche locale active : `main` ;
- branche par defaut GitHub : `main` ;
- branche beta : `beta-v2` ;
- `main` et `beta-v2` pointent sur le commit `a6780aa` ;
- tag beta : `v2-beta1` ;
- release GitHub beta : `https://github.com/Yuzuctus/RandomFavorites/releases/tag/v2-beta1` ;
- workflow beta reussi : `https://github.com/Yuzuctus/RandomFavorites/actions/runs/31273699913` ;
- les autres branches locales et distantes ont ete supprimees ;
- les anciens tags historiques sont conserves ;
- le depot de travail etait propre apres la publication.

Le tag `v2-beta1` a publie ces artefacts :

- `YuzuctusVencordSetup.exe` ;
- `YuzuctusVencordSetup.exe.sha256` ;
- `YuzuctusVencordBundle.zip` ;
- `YuzuctusVencordBundle.zip.sha256` ;
- `YuzuctusVencordBundle.manifest.json`.

## Point important sur Vencord

V2 n'est pas encore un fork GitHub `Yuzuctus/Vencord`. Le pipeline recupere actuellement le Vencord officiel depuis
`Vendicated/Vencord`, puis y materialise les plugins du catalogue avant compilation.

Il faut donc parler techniquement d'une **distribution Yuzuctus Vencord** et non d'un fork Yuzuctus Vencord tant
qu'un depot fork separe n'est pas cree.

Le manifeste de chaque build enregistre le depot Vencord et son commit exact.

## Architecture modulaire

### Catalogue

Le fichier `catalog/plugins.json` est la source de verite des plugins inclus dans une release.

Le schema actuel est `schemaVersion: 1`. Chaque entree contient :

- `id` : identifiant du dossier Vencord, par exemple `randomFavorites` ;
- `displayName` : nom affiche ;
- `repository` : depot source declare ;
- `sourcePath` : dossier source local relatif a la racine de la distribution ;
- `entrypoint` : fichier d'entree, actuellement `index.tsx` ;
- `files` : fichiers et dossiers a copier ;
- `settingsKey` : cle de reglages Vencord ;
- `license` et `licenseFile` ;
- `maintainer` et `status`.

Le catalogue actuel contient une seule entree : `randomFavorites`.

Son implementation se trouve dans :

- `index.tsx` a la racine, qui sert d'entrypoint de compatibilite ;
- `Plugin RandomFavorites/index.tsx`, integration Vencord principale ;
- `Plugin RandomFavorites/messageFormatting.ts` et ses tests ;
- `Plugin RandomFavorites/shuffleBag.ts` et ses tests ;
- `Plugin RandomFavorites/uniformRandom.ts` et ses tests.

Le dossier avec espace `Plugin RandomFavorites` est volontairement conserve pour cette migration. Il ne faut pas
le renommer sans mettre a jour `catalog/plugins.json` et le code d'export de `index.tsx`.

### Materialisation

Le script `scripts/Materialize-Plugins.ps1` lit le catalogue et copie chaque entree dans un dossier direct de
Vencord :

```text
vencord/src/userplugins/<pluginId>
```

Pour RandomFavorites, le resultat attendu est :

```text
vencord/src/userplugins/randomFavorites/index.tsx
vencord/src/userplugins/randomFavorites/Plugin RandomFavorites/...
```

Le script :

- valide les IDs et les chemins relatifs ;
- refuse les doublons ;
- refuse les chemins qui sortent de la racine source ;
- supprime le dossier cible du plugin avant materialisation ;
- verifie l'entrypoint final ;
- ne charge aucun code distant.

Le script supporte actuellement des sources presentes dans `SourceRoot`. Le champ `repository` est deja present
pour preparer la modularite, mais le clonage automatique de depots de plugins externes n'est pas encore implemente.

### Build et manifeste

Le script `scripts/Build-ReleaseBundle.ps1` est maintenant generique pour la distribution. Il :

- lit et valide le catalogue ;
- calcule le commit Git de la distribution ;
- recupere le commit et le depot du checkout Vencord ;
- calcule `pluginsDigest` sur la liste resolue des plugins ;
- copie le catalogue dans le bundle ;
- construit un manifeste schema 2 ;
- verifie OpenAsar par le digest SHA-256 publie ;
- verifie le Vencord Installer CLI par son checksum ;
- produit les bundles `YuzuctusVencord*`.

Le manifeste schema 2 contient notamment :

- `productId: YuzuctusVencord` ;
- `productName: Yuzuctus Vencord` ;
- `version` ;
- `vencordRepository` et `vencordCommit` ;
- `distributionCommit` ;
- `pluginsDigest` ;
- `plugins[]` avec les metadonnees de chaque plugin ;
- les informations OpenAsar ;
- les fichiers obligatoires du bundle.

Le champ legacy `pluginCommit` est encore emis pour faciliter la lecture des anciennes versions.
`BundleManifestValidator` accepte les manifests schema 1 et schema 2.

## Installateur Windows

Le projet WPF se trouve encore dans les dossiers internes `installer/RandomFavorites.Setup*`, mais son identite
utilisateur est Yuzuctus Vencord.

Changements principaux :

- titre, textes, dialogues et accessibilite rebrandes ;
- assembly publie sous `YuzuctusVencordSetup.exe` ;
- stockage principal dans `%LOCALAPPDATA%\\YuzuctusVencord` ;
- migration de l'ancien `%LOCALAPPDATA%\\RandomFavorites` ;
- affichage de la liste des plugins inclus au lieu d'un champ mono-plugin ;
- comparaison des builds par `pluginsDigest` ;
- suppression generique des reglages des plugins geres ;
- mode de desinstallation `ManagedPluginsOnly` au lieu de `RandomFavoritesOnly` ;
- conservation des reglages non geres ;
- sauvegarde des reglages avant suppression.

L'ancien fichier `Installer RandomFavorites.cmd` est conserve comme lanceur legacy. Le lanceur recommande est :

```text
Installer Yuzuctus Vencord.cmd
```

Le nom interne `scripts/RandomFavoritesManager.ps1` est aussi conserve pour compatibilite. Le manager utilise
desormais un dossier de distribution complet, puis appelle `Materialize-Plugins.ps1`.

## Manager PowerShell

`scripts/RandomFavoritesManager.ps1` orchestre :

- les prerequis ;
- le checkout Vencord ;
- le checkout de la distribution ;
- la lecture du catalogue ;
- la materialisation des plugins ;
- le build Vencord ;
- l'injection Discord optionnelle ;
- les logs et l'etat local.

Le dossier par defaut est `%LOCALAPPDATA%\\YuzuctusVencord`.

Le parametre public `PluginRepository` est conserve comme alias de `DistributionRepository` pour les anciens appels.
Le manager genere maintenant `Update Yuzuctus Vencord.cmd` et un script gere dans le dossier `manager`.

## CI et publications

### `ci.yml`

La CI :

- checkout la distribution dans `distribution` ;
- checkout le Vencord officiel dans `vencord` ;
- materialise le catalogue ;
- installe les dependances pnpm ;
- execute les tests TypeScript des plugins ;
- execute ESLint sur `src/userplugins` ;
- execute `pnpm testTsc` ;
- construit Vencord ;
- compile et publie l'installateur Windows.

### `beta-release.yml`

Le workflow beta est le seul workflow de release. Il est declenche par :

- `v2-beta1` et autres tags `vN-betaN` ;
- les tags SemVer beta comme `v2.0.0-beta.1`.

Il execute les tests, compile Vencord, construit le bundle, publie l'EXE et cree une GitHub prerelease.

Les anciens workflows `release.yml` et `refresh-vencord.yml` ont ete supprimes pour eviter toute publication stable
ou mise a jour automatique d'une release stable.

## Verification effectuee

Les verifications suivantes ont ete executees sur cette V2 :

- build .NET de l'installateur : reussi ;
- publication self-contained win-x64 : reussie ;
- executable genere : `YuzuctusVencordSetup.exe` ;
- tests smoke de l'installateur : `22/22` ;
- parser PowerShell pour `Build-ReleaseBundle.ps1` : reussi ;
- parser PowerShell pour `Materialize-Plugins.ps1` : reussi ;
- parser PowerShell pour `RandomFavoritesManager.ps1` : reussi ;
- test fixture du materialiseur : reussi ;
- validation du format de tag `v2-beta1` : reussie ;
- workflow GitHub beta `v2-beta1` : reussi.

Les tests TypeScript complets et le build Vencord local ne sont pas executes dans ce depot seul, car les dependances
Vencord ne sont pas installees localement. Ils sont executes par GitHub Actions dans un checkout Vencord frais.

## Continuer le developpement

### Ajouter un plugin cree dans ce depot

1. Creer un dossier source propre pour le plugin.
2. Ajouter son entrypoint et ses tests.
3. Ajouter une entree dans `catalog/plugins.json`.
4. Declarer `id`, `entrypoint`, `files`, `settingsKey`, `license` et `licenseFile`.
5. Verifier que l'ID est unique et compatible avec un dossier `src/userplugins/<id>`.
6. Lancer la materialisation dans un checkout Vencord.
7. Lancer tests, ESLint, typecheck et build.
8. Verifier le manifeste et le digest du catalogue.

### Ajouter un plugin externe ou communautaire

Ce cas est prepare mais pas encore livre. Il faudra d'abord implementer :

- un resolver de depots externes ;
- un commit obligatoire et immuable ;
- une verification du contenu et du hash source ;
- la gestion des licences et notices ;
- les dependances et conflits entre plugins ;
- un niveau de confiance explicite ;
- une execution CI avant inclusion dans une beta.

Ne pas faire croire qu'un plugin tiers est sandboxe. Un plugin Vencord s'execute dans le processus Discord et doit
etre traite comme du code privilegie.

### Publier une nouvelle beta

1. Travailler sur `beta-v2` ou une branche temporaire locale.
2. Modifier le catalogue ou le code necessaire.
3. Executer les verifications locales.
4. Fusionner ou fast-forwarder `main` selon la strategie choisie.
5. Creer un tag beta, par exemple `v2-beta2`.
6. Pousser le tag pour declencher uniquement `beta-release.yml`.
7. Verifier la prerelease et ses cinq artefacts.

Le projet ne doit pas reintroduire de workflow de release stable tant que la beta n'est pas validee.

## Limites actuelles

- RandomFavorites est le seul plugin integre ;
- Vencord reste recupere depuis `Vendicated/Vencord` ;
- le catalogue ne clone pas encore de depots externes ;
- l'installateur inclut tous les plugins du catalogue et leur activation se fait dans les reglages Vencord ;
- les namespaces et noms de projets C# internes gardent `RandomFavorites.Setup` ;
- le depot GitHub s'appelle encore `Yuzuctus/RandomFavorites` ;
- l'icone de l'installateur utilise encore le chemin interne `Assets/RandomFavorites.ico` ;
- l'EXE n'est pas signe ;
- les dependances Node/Vencord ne sont pas vendues dans le depot de distribution.

## Regles de securite a conserver

- ne jamais lire, loguer, stocker ou transmettre de token Discord ;
- ne jamais ajouter de telemetrie, analytics ou publicite ;
- ne jamais envoyer de contenu sans action explicite ;
- ne pas modifier les listes natives de favoris Discord ;
- ne pas contourner les permissions d'envoi ;
- ne pas integrer un plugin tiers sans licence, commit et revue ;
- ne pas revendiquer une compatibilite Vencord sans compilation contre un checkout actuel.

## Reprise rapide pour une autre IA

Commencer par lire, dans cet ordre :

1. `V2_HANDOFF.md` ;
2. `AGENTS.md` ;
3. `catalog/plugins.json` ;
4. `scripts/Materialize-Plugins.ps1` ;
5. `scripts/Build-ReleaseBundle.ps1` ;
6. `.github/workflows/beta-release.yml` ;
7. `installer/RandomFavorites.Setup.Core/Models/InstallerModels.cs` ;
8. `installer/RandomFavorites.Setup.Core/Services/InstallerService.cs`.

Ne pas repartir de l'ancien objectif « installer RandomFavorites ». Le bon perimetre est : **maintenir une
distribution Yuzuctus Vencord beta, modulaire, avec RandomFavorites comme premier et unique plugin actuel**.
