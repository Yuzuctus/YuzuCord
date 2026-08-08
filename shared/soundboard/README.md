# Bibliothèque Soundboard partagée

Cette bibliothèque fournit aux plugins Yuzuctus une seule implémentation de l’envoi Soundboard dans le chat :

- chargement partagé des sons par l’action native Discord, avec l’analytique facultative désactivée ;
- snapshot stable d’un son et normalisation du nom de fichier ;
- URL générée par le module CDN natif Discord et limitée aux domaines CDN Discord en HTTPS ;
- contrôles de permission, taille, format audio, timeout et disponibilité ;
- upload via la file native Discord, avec prise en charge de la réponse en cours ;
- aucune dépendance à un salon vocal.

`src/attachment.ts` et `src/loader.ts` restent purs et testables sans Discord. `src/runtime.ts` contient les
adaptateurs Vencord/Discord. Le catalogue copie la bibliothèque dans `_shared/soundboard/` pour chaque plugin
consommateur afin que chaque plugin reste autonome dans `src/userplugins/<id>`.
