# Yuzuctus Vencord

Une distribution personnalisée de Vencord pour Windows. Le catalogue actuel contient uniquement le plugin
**RandomFavorites**, mais la compilation et l'installateur sont déjà structurés pour accueillir plusieurs
plugins indépendants.

## Statut

Le projet est actuellement distribué uniquement en **beta**. La release de cette migration utilise le tag
`v2-beta1`.

## Installer sur Windows

1. Télécharge **YuzuctusVencordSetup.exe** depuis la release beta officielle.
2. Ouvre le fichier et choisis ta version de Discord.
3. Coche **OpenAsar** si tu veux aussi installer cette optimisation facultative.
4. Clique sur **Installer**.
5. Dans Discord, va dans `Paramètres > Vencord > Plugins` et active **RandomFavorites**.

Git, Node.js et pnpm ne sont pas nécessaires pour l'installation du bundle beta. L'installateur vérifie le
bundle avec SHA-256 avant de modifier Discord.

> L'application n'est pas encore signée. Si Windows SmartScreen apparaît, vérifie que le fichier vient bien
> de la page Releases officielle, puis choisis **Informations complémentaires > Exécuter quand même**.

## Plugin actuel

**RandomFavorites** envoie un GIF, une emote, un sticker ou un son de soundboard aléatoire depuis Discord.

- Clic gauche sur le dé : effectue le tirage configuré.
- Clic droit sur le dé : choisit la catégorie et le mode de tirage.
- L'aperçu sécurisé demande une confirmation avant tout envoi ou toute lecture.
- Les réglages sont en français si Discord est en français, sinon en anglais.

Les fichiers du plugin restent dans `Plugin RandomFavorites`. Le catalogue `catalog/plugins.json` décrit son
identifiant, sa source, son point d'entrée, sa licence et les fichiers à intégrer. Un futur plugin sera ajouté
comme une nouvelle entrée sans modifier le cœur de l'installateur.

## Mettre à jour, réparer ou désinstaller

Rouvre le même EXE beta :

- **Installer / Mettre à jour** récupère la dernière build beta vérifiée ;
- **Réparer** réapplique la build sans supprimer les réglages ;
- **Désinstaller** peut retirer les plugins gérés, Vencord en conservant ses données, ou tout supprimer.

OpenAsar reste facultatif. Les réglages des plugins gérés sont sauvegardés avant leur suppression. Les anciennes
installations RandomFavorites restent reconnues comme installations legacy ; la nouvelle distribution utilise
son propre dossier `%LOCALAPPDATA%\\YuzuctusVencord`.

## Développement

Le projet ne contient pas de dépendances Node locales. Il est matérialisé dans un checkout Vencord avant la
compilation :

```text
vencord/src/userplugins/<pluginId>
```

Le script `scripts/Materialize-Plugins.ps1` lit le catalogue et copie chaque plugin dans son propre dossier.
Le pipeline beta exécute ensuite les tests, ESLint, le typecheck et le build Vencord.

Pour reprendre l'architecture et le travail avec une autre IA, lire `V2_HANDOFF.md`.

## Sécurité et licences

- aucun token Discord n'est lu, stocké ou transmis par cette distribution ;
- aucune télémétrie ni publicité n'est ajoutée par l'installateur ;
- rien n'est envoyé sans action explicite de l'utilisateur ;
- les plugins tiers futurs devront être épinglés sur un commit et déclarer leur licence ;
- un plugin Vencord s'exécute dans le processus Discord et doit donc être approuvé avant son intégration.

Yuzuctus Vencord et RandomFavorites sont publiés sous licence `GPL-3.0-or-later`. Les composants tiers sont
documentés dans `installer/THIRD_PARTY_NOTICES.md`.

Le fichier `Installer RandomFavorites.cmd` est conservé comme ancien lanceur. La nouvelle entrée recommandée
est `Installer Yuzuctus Vencord.cmd`.
