# YuzuCord

Une distribution personnalisée de Vencord pour Windows, construite à partir du Vencord officiel courant et
d'un catalogue modulaire de plugins sélectionnés par Yuzuctus.

## Installation

1. Télécharge [`YuzuCordSetup.exe`](https://github.com/Yuzuctus/YuzuCord/releases/latest/download/YuzuCordSetup.exe)
   depuis la dernière release stable GitHub.
2. Ouvre-le et choisis ta version de Discord.
3. Active OpenAsar si tu souhaites cette optimisation facultative.
4. Clique sur **Installer**.
5. Dans `Paramètres Discord > Vencord > Plugins`, active les plugins Yuzuctus souhaités.

Git, Node.js et pnpm ne sont pas nécessaires avec l’installateur. Le bundle et ses composants sont contrôlés
par SHA-256 avant l’installation.

L’application n’est pas encore signée. Si SmartScreen apparaît, vérifie que l’EXE vient bien de la page
Releases officielle avant de choisir **Informations complémentaires > Exécuter quand même**.

## Plugins inclus

### RandomFavorites

Envoie un GIF favori, une emote, un sticker ou un son de Soundboard aléatoire.

- clic gauche sur le dé : lance le tirage configuré ;
- clic droit : sélectionne les catégories et le mode de tirage ;
- aperçu sécurisé facultatif avant l’envoi ;
- répartition équitable entre les catégories sélectionnées et anti-répétition adaptatif ;
- Soundboard aléatoire disponible dans le chat et dans le sélecteur vocal FavoriteRandom.

### SoundboardChat

Ajoute **Soundboard** comme quatrième onglet natif à côté des GIF, emotes et stickers. Un clic sur un son
l’envoie comme fichier audio dans le salon texte actuel, sans demander d’être connecté à un vocal.

Le plugin réutilise entièrement la recherche, les favoris, les catégories de serveurs, les aperçus et le style
de Discord. Il vérifie les permissions d’envoi et de pièces jointes avant tout upload. Aucun son n’est envoyé
sans un clic explicite.

Les réglages des deux plugins sont indépendants et s’affichent en français lorsque Discord est en français,
sinon en anglais.

Les plugins créés par Yuzuctus portent le tag **YuzuMod**. Les plugins provenant d'autres développeurs portent
le tag **ThirdParty**. Ces tags apparaissent dans les informations et les filtres de Vencord afin de distinguer
clairement les créations Yuzuctus, les intégrations externes et les plugins Vencord officiels.

## Mettre à jour, réparer ou désinstaller

Rouvre le même EXE :

- **Installer / Mettre à jour** récupère la build stable vérifiée associée à l'installateur ;
- **Réparer** réapplique la build sans supprimer les réglages ;
- **Désinstaller** peut retirer seulement les plugins gérés, Vencord en conservant ses données, ou l’ensemble.

Les réglages supprimés sont sauvegardés. OpenAsar reste facultatif et indépendant des plugins.

## Développement

Les sources sont séparées dans `plugins/<pluginId>` et les fonctions communes dans `shared/`. Le catalogue
compose chaque plugin dans un Vencord officiel courant avant les tests et le build :

```text
vencord/src/userplugins/<pluginId>
```

Le catalogue accepte les plugins développés ici et les plugins externes figés sur un commit et une empreinte.
La procédure complète se trouve dans [catalog/README.md](catalog/README.md). L’architecture générale et la
passation technique se trouvent dans [V2_HANDOFF.md](V2_HANDOFF.md).

Les branches de travail utilisent `feature/<nom>` pour une fonctionnalité et `fix/<nom>` pour une correction.
Les préfixes propres aux outils ou aux assistants ne sont pas utilisés dans ce dépôt.

## Sécurité et licences

- aucun token Discord n’est lu, stocké ou transmis ;
- aucune télémétrie ni publicité n’est ajoutée ;
- aucun envoi n’a lieu sans action explicite ;
- les permissions Discord ne sont jamais contournées ;
- tout plugin externe exige une licence, un commit immuable, une empreinte et une revue humaine.

YuzuCord et les plugins inclus dans ce dépôt sont publiés sous licence `GPL-3.0-or-later`. Les composants
tiers du bundle sont listés dans `installer/THIRD_PARTY_NOTICES.md`.
