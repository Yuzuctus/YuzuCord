# Catalogue des plugins

`plugins.json` est l’unique source de vérité des plugins inclus dans YuzuCord. Son schéma public est
`plugins.schema.json` (version 2).

Le matérialiseur résout chaque entrée dans un dossier indépendant :

```text
vencord/src/userplugins/<pluginId>/
```

Il valide d’abord toutes les sources, construit tous les plugins dans une zone temporaire, puis les déploie en
une transaction. Un échec restaure les versions précédemment installées. Les userplugins qui ne figurent pas
dans le manifeste Yuzuctus précédent ne sont jamais supprimés.

## Organisation recommandée

```text
plugins/
  monPlugin/
    index.tsx
    feature.ts
    feature.test.ts
shared/
  monDomaine/
    src/
    tests/
catalog/
  plugins.json
  plugins.schema.json
```

Les `mappings` composent le contenu final du plugin. Ils permettent d’ajouter son dossier, une bibliothèque
partagée et la licence. Le matérialiseur génère ensuite automatiquement le petit wrapper de distribution et
le tag correspondant à la provenance déclarée :

```json
{
  "id": "monPlugin",
  "displayName": "MonPlugin",
  "source": {
    "type": "local",
    "path": ".",
    "repository": "https://github.com/Yuzuctus/MonProjet.git"
  },
  "mappings": [
    { "from": "plugins/monPlugin", "to": "." },
    { "from": "shared/monDomaine/src", "to": "_shared/monDomaine/src" },
    { "from": "LICENSE", "to": "LICENSE" }
  ],
  "entrypoint": "index.tsx",
  "settingsKey": "MonPlugin",
  "provenance": "yuzuctus",
  "dependencies": [],
  "conflicts": [],
  "license": "GPL-3.0-or-later",
  "licenseFile": "LICENSE",
  "maintainer": "Yuzuctus",
  "status": "experimental"
}
```

## Intégrer un plugin externe

Une source externe doit être un dépôt GitHub public en HTTPS, figé sur un commit complet de 40 caractères.
Elle déclare aussi la personne et la date de la revue :

```json
"source": {
  "type": "git",
  "repository": "https://github.com/auteur/plugin.git",
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "integrity": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
  "review": {
    "approvedBy": "Yuzuctus",
    "reviewedAt": "2026-08-08"
  }
}
```

Après avoir relu le code, la licence et les fichiers sélectionnés par `mappings`, calcule l’empreinte exacte :

```powershell
.\scripts\Get-PluginIntegrity.ps1 `
  -CatalogPath .\catalog\plugins.json `
  -PluginId monPluginExterne
```

Remplace ensuite la valeur temporaire par le `sha256:...` affiché. Le build refuse le plugin si le commit ou
un seul fichier matérialisé diffère. Les symlinks, sous-modules, jonctions, pointeurs Git LFS non résolus,
chemins sortants et destinations en collision sont refusés. Aucun hook Git du dépôt externe n’est exécuté.

Un plugin tiers s’exécute dans Discord avec les mêmes droits qu’un autre plugin Vencord : l’empreinte garantit
la reproductibilité, pas l’innocuité. La revue humaine reste obligatoire.

## Dépendances et conflits

- `dependencies` contient les IDs qui doivent être présents ; le matérialiseur trie automatiquement l’ordre.
- une dépendance absente ou un cycle bloque le build ;
- `conflicts` bloque une combinaison explicitement incompatible ;
- `settingsKey` permet à l’installateur de retirer uniquement les réglages des plugins gérés.
- `provenance: "yuzuctus"` ajoute le tag `YuzuMod`, réservé aux plugins créés par Yuzuctus ;
- `provenance: "thirdParty"` ajoute le tag `ThirdParty` aux intégrations externes, sans les présenter comme
  des créations Yuzuctus ou des plugins Vencord officiels.

## Vérifier une modification

Depuis le dépôt de distribution :

```powershell
.\scripts\Test-PluginCatalog.ps1
.\scripts\Materialize-Plugins.ps1 `
  -CatalogPath .\catalog\plugins.json `
  -SourceRoot . `
  -VencordDirectory C:\chemin\vers\Vencord
```

Puis, depuis Vencord :

```text
pnpm exec tsx --test "src/userplugins/**/*.test.ts"
pnpm eslint src/userplugins
pnpm testTsc
pnpm build
```

Le résultat résolu et ses empreintes sont enregistrés dans
`vencord/src/userplugins/.yuzuctus/resolved-plugins.json`. Le bundle de release utilise directement ce fichier
vérifié pour produire son manifeste, au lieu de refaire confiance au catalogue brut.
