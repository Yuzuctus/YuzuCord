# Passation V2 — YuzuCord

Ce dépôt n’est plus un simple installateur de RandomFavorites. YuzuCord est une distribution Windows de Vencord
construite à partir du Vencord officiel courant et d’un catalogue de plugins Yuzuctus.

La distribution stable est publiée depuis `main`. La branche historique `beta-v2` reste disponible pour les
anciennes préversions, mais n'est plus la branche de référence. Le dépôt GitHub public est `Yuzuctus/YuzuCord`.

Les branches de travail suivent `feature/<nom>` ou `fix/<nom>`. Ne pas créer de branche préfixée par le nom
d’un outil ou d’un assistant.

## Objectif produit

- construire un Vencord Yuzuctus reproductible sans maintenir un fork complet de Vencord ;
- ajouter ou retirer des plugins sans réécrire l’installateur ;
- accepter des plugins développés dans ce dépôt et des plugins publics existants ;
- tester systématiquement le catalogue contre la dernière version officielle de Vencord ;
- distribuer un EXE autonome : Git, Node.js et pnpm ne sont pas requis chez l’utilisateur ;
- préserver les plugins Vencord non gérés et les réglages que l’utilisateur choisit de conserver.

## Plugins intégrés

### RandomFavorites

`plugins/randomFavorites/` contient le tirage aléatoire de GIF, emotes, stickers et sons de Soundboard, les
commandes, le bouton de chat, l’aperçu sécurisé, la répartition des types, l’anti-répétition adaptatif et le
serveur virtuel FavoriteRandom du sélecteur Soundboard vocal.

### SoundboardChat

`plugins/soundboardChat/` est un plugin indépendant. Il expose l’onglet Soundboard natif comme quatrième onglet
du sélecteur GIF/emote/sticker et transforme la sélection explicite d’un son en fichier audio envoyé dans le
salon texte. Il ne demande ni vocal, ni `SPEAK`, ni `USE_SOUNDBOARD`.

Le plugin réutilise le composant Discord natif : recherche, favoris, catégories de serveurs, lecture d’aperçu,
clavier, accessibilité et CSS restent gérés par Discord. Son patch cible le callback stable
`"soundboard_picker"` et les propriétés `SOUNDBOARD`; un test reproduit la forme minifiée Discord courante.

RandomFavorites détecte l’ouverture de l’onglet Soundboard d’expression et n’y injecte pas sa catégorie vocale
FavoriteRandom. Les deux fonctions restent donc indépendantes.

## Catalogue modulaire

`catalog/plugins.json` utilise `schemaVersion: 2`. `catalog/plugins.schema.json` documente sa forme.

Chaque entrée contient :

- une identité stable, un nom, une clé de réglages, un mainteneur et un statut ;
- une source `local` ou `git` ;
- des `mappings` source → destination ;
- un point d’entrée et un fichier de licence ;
- une provenance `yuzuctus` ou `thirdParty`, transformée automatiquement en tag `YuzuMod` ou `ThirdParty`
  dans le registre et les métadonnées du plugin ;
- des dépendances et conflits explicites.

Une source Git externe doit utiliser un dépôt GitHub public en HTTPS, un commit complet, une empreinte SHA-256
des fichiers matérialisés et les métadonnées de revue. `scripts/Get-PluginIntegrity.ps1` calcule cette empreinte
après checkout sécurisé. Les hooks, sous-modules, symlinks, jonctions et pointeurs Git LFS sont refusés.

Les dépendances sont triées topologiquement. Une dépendance absente, un conflit présent ou un cycle arrête le
build avant toute mutation de Vencord.

## Matérialisation

`scripts/PluginCatalog.psm1` contient le moteur commun. `scripts/Materialize-Plugins.ps1` n’est qu’un point
d’entrée CLI.

Le moteur :

1. valide tout le catalogue et ses chemins ;
2. récupère les sources Git immuables sans exécuter leurs hooks ;
3. applique les mappings dans une zone temporaire par plugin ;
4. vérifie le point d’entrée, la licence et l’intégrité ;
5. génère un wrapper stable qui conserve le point d’entrée original et applique les tags de distribution ;
6. calcule une empreinte déterministe par plugin et une empreinte globale ;
7. verrouille les lancements concurrents ;
8. sauvegarde les plugins précédemment gérés, déploie tous les nouveaux et restaure les sauvegardes si une
   étape échoue ;
9. ne supprime jamais un userplugin absent de l’ancien manifeste Yuzuctus ;
10. écrit `src/userplugins/.yuzuctus/resolved-plugins.json`.

Le manifeste résolu est la preuve utilisée par le build et le manager. Le hash du JSON de catalogue brut n’est
plus utilisé comme identité de payload.

## Bibliothèques partagées

`shared/soundboard/` centralise le chargement et l’envoi audio Soundboard. Ses sources sont injectées dans les
plugins consommateurs sous `_shared/soundboard/` par les mappings du catalogue.

Cette stratégie évite une dépendance runtime entre userplugins et garde chaque dossier matérialisé autonome.
Les sources restent maintenues une seule fois dans ce dépôt.

## Build et manifeste de release

`scripts/Build-ReleaseBundle.ps1` :

- exige par défaut des checkouts Git propres ;
- rematérialise le catalogue avant de construire le bundle ;
- utilise directement le résultat résolu ;
- copie les licences réellement matérialisées ;
- récupère et vérifie l’installateur Vencord officiel et OpenAsar ;
- émet un manifeste bundle `schemaVersion: 3`.

Le schéma 3 ajoute `catalogSchemaVersion`, `sourceType`, `sourceDigest`, `dependencies` et `conflicts` pour chaque
plugin. L’installateur continue de lire les anciens schémas 1 et 2.

## Installateur et manager

Le produit visible est YuzuCord, même si certains namespaces C#, l’identifiant interne `YuzuctusVencord` et le nom
`RandomFavoritesManager.ps1` restent historiques pour préserver la compatibilité.

L’installateur WPF :

- télécharge le bundle de la release associée à l'installateur et le vérifie ;
- compare les installations par `pluginsDigest` et commit Vencord ;
- affiche les plugins inclus ;
- installe, met à jour, répare ou désinstalle ;
- peut supprimer uniquement les réglages dont les `settingsKey` figurent dans le manifeste ;
- gère OpenAsar indépendamment ;
- migre les anciennes installations RandomFavorites.

Le manager source (`scripts/RandomFavoritesManager.ps1`) clone ou met à jour le dépôt de distribution et le
Vencord officiel, matérialise le catalogue, installe les dépendances exactes, compile puis injecte. Son état est
désormais alimenté par `resolved-plugins.json`.

## CI et releases

`.github/workflows/ci.yml` s’exécute sur `main`, `beta-v2`, les pull requests et chaque semaine. Il :

- teste le moteur du catalogue, y compris source externe, verrou et rollback ;
- matérialise les plugins dans le dernier Vencord ;
- exécute les tests TypeScript, ESLint, `testTsc` et le build ;
- valide les scripts avec Windows PowerShell ;
- compile et teste l’installateur.

`.github/workflows/release.yml` accepte les tags stables et beta. Il refait les mêmes contrôles, construit le
bundle et l’EXE autonome, puis publie une release stable ou une pre-release selon le tag.

## Ajouter un plugin local

1. créer `plugins/<id>/index.tsx` et ses tests ;
2. placer les fonctions réutilisables dans `shared/<domaine>/` ;
3. ajouter l’entrée locale et ses mappings au catalogue ;
4. déclarer les dépendances, conflits, licence et `settingsKey` ;
5. exécuter les tests du catalogue puis la matrice Vencord complète.

Les détails et exemples JSON sont dans `catalog/README.md`.

## Ajouter un plugin externe

1. vérifier sa licence et sa compatibilité Vencord ;
2. relire le code complet au commit choisi, notamment les requêtes réseau et l’accès aux données Discord ;
3. ajouter une source Git figée avec les métadonnées de revue ;
4. limiter les mappings aux fichiers nécessaires ;
5. calculer l’intégrité avec `scripts/Get-PluginIntegrity.ps1` ;
6. exécuter tous les tests et faire une validation manuelle en VM.

L’empreinte n’est pas une sandbox. Un plugin Vencord s’exécute dans le processus Discord.

## Commandes de validation

Depuis ce dépôt :

```powershell
.\scripts\Test-PluginCatalog.ps1
```

Après matérialisation dans un Vencord courant :

```text
pnpm exec tsx --test "src/userplugins/**/*.test.ts"
pnpm eslint src/userplugins
pnpm testTsc
pnpm build
```

Pour l’installateur :

```text
dotnet build installer/RandomFavorites.Setup/RandomFavorites.Setup.csproj -c Release
dotnet run --project installer/RandomFavorites.Setup.SmokeTests/RandomFavorites.Setup.SmokeTests.csproj -c Release
```

## Vérification de cette migration

La migration modulaire et SoundboardChat ont été contrôlés avec :

- validation JSON Schema du catalogue ;
- tests d’intégration PowerShell du catalogue, de la source Git, de l’intégrité, du verrou et du rollback ;
- parser Windows PowerShell 5.1 sur tous les scripts ;
- 53 tests TypeScript réussis ;
- ESLint sans erreur ;
- `testTsc` sans erreur ;
- build de production du Vencord officiel courant réussi ;
- correspondance des deux patchs SoundboardChat dans le bundle Discord courant observé ;
- build .NET sans avertissement et 26/26 smoke tests installateur réussis ;
- smoke test complet du manager avec les deux IDs résolus et `-SkipInject`, sans modification de Discord.

## Garde-fous à conserver

- ne jamais lire, journaliser, stocker ou transmettre un token Discord ;
- ne pas ajouter de télémétrie ou de service tiers dans les plugins ;
- ne pas modifier les listes natives de favoris ;
- ne rien envoyer sans clic ou commande explicite ;
- ne jamais contourner les permissions de salon ;
- ne pas publier une compatibilité sans compiler contre un Vencord officiel courant ;
- ne pas intégrer une source externe sans licence, commit immuable, empreinte et revue.

## Limites connues

- SoundboardChat dépend de la structure minifiée du sélecteur Discord ; la CI détecte la plupart des ruptures,
  mais une validation visuelle et fonctionnelle en VM reste nécessaire ;
- l’EXE stable n’est pas signé ;
- les noms de projets C# et certains chemins internes conservent encore l’identité historique RandomFavorites ;
- l’ajout ou la suppression de plugins change le bundle complet : il n’existe pas encore de sélection de
  plugins au moment de l’installation.
