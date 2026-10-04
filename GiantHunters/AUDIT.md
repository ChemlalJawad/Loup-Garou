# Giant Hunters : rapport d'audit

Trois audits en lecture seule (mécaniques et code, map et performances,
modèles et design des titans), faits sur `main` @ e41c19e. Rien n'a encore
été testé dans Studio : tout vient de la lecture du code et de simulations
hors Roblox (les mocks du scratchpad).

Priorités :
- **P0** : casse le jeu.
- **P1** : nécessaire pour un jeu complet.
- **P2** : finition.

## Chiffres clés

| Mesure | Valeur |
|---|---|
| Instances dans la map | 12 111 (10 591 parts, 1 094 modèles) |
| Arbres géants | 187, ~19 parts chacun, soit 3 519 parts (1/3 de la map) |
| Lumières | 262 PointLight, 102 Fire, 12 ParticleEmitter |
| Parts qui projettent une ombre | 6 687 (dont 811 minces) |
| CanTouch laissé à true | 6 715 parts, alors qu'aucun script n'utilise Touched |
| Feuillages collidables | 1 479 |
| Titan | 61 à 81 parts ; une vague complète ≈ 1 200 parts et 17 lumières |
| Joueur (tenue + épées) | ~84 parts |
| Terrain hors de portée d'un point d'accroche (170 studs) | 19,6 % |
| Distance médiane jusqu'à une caisse | 215 studs (pire cas : 834) |
| StreamingEnabled | **désactivé** (tout est téléchargé sur mobile) |

## 1. Mécaniques et code

### P0
- **Se libérer sur mobile ne marche pas.** La barre se remplit au tap, mais
  le serveur ne compte que l'action liée : l'enfant est toujours attrapé.
  Le serveur doit compter tout input, et la barre doit suivre le compteur
  serveur.
- **Respawn pendant une prise.** L'état `held` survit au respawn : le corps
  tremble dans la main, puis il y a un double respawn. Il faut relâcher à la
  mort, au respawn et au `CharacterRemoving`.
- **Shift-lock inaccessible.** Le Dash est sur LeftShift, la touche du
  shift-lock. Déplacer le Dash ou ajouter une caméra de combat verrouillée.
- **Visée à la manette décalée.** Elle utilise la souris : il faut viser au
  centre de l'écran à la manette.

### P1 : sécurité
- La position et la vitesse des coupes viennent du client : un tricheur peut
  se téléporter sur la nuque. Suivre la position côté serveur et calculer la
  vitesse côté serveur.
- Le relais des crochets n'a pas de limite de débit (spam vers tout le
  serveur). La fusée éclairante ne vérifie pas que le joueur est vivant.

### P1 : bugs
- Pas de `SetNetworkOwner` après une prise.
- États FallingDown et Ragdoll non désactivés.
- `CharacterUseJumpPower` n'est pas forcé.
- Le pouvoir de titan n'expire jamais, et on ne peut pas refuser le choix de
  camp.
- Le camp des titans peut farmer les joueurs : +2 points par KO, sans
  immunité.
- Les ProximityPrompts utilisent E et X, déjà pris par le crochet droit et la
  coupe.
- `LoadCharacterAsync` n'est pas protégé par un `pcall`.
- Les câbles des autres joueurs restent après leur mort.
- Le cooldown de coupe serveur égale celui du client, donc des coupes
  légitimes sont rejetées.
- La hitbox de la nuque côté serveur n'est pas animée : elle peut être à
  ~5 studs de ce qu'on voit.
- Une erreur dans Wall, Town ou Wilds tue tout le serveur (`pcall` seulement
  sur Ground). Supprimer automatiquement Baseplate et SpawnLocation.

### P1 : jeu complet
- **Pas de défaite.** Il faut une vie du district, un écran « DISTRICT
  TOMBÉ » et une limite de temps par vague. Aujourd'hui, un titan isolé
  bloque la manche.
- **Les vagues ne dépendent pas du nombre de joueurs.** `MaxAlive` n'est pas
  appliqué.
- **Pas de sauvegarde.** Ajouter un DataStore pour les points, le rang, les
  titans abattus et la meilleure manche.
- **Pas de tutoriel.** Ajouter un guide de première partie (crochet, reel,
  coupe d'un mannequin, ravitaillement) qui mène au Terrain d'entraînement.
- **Interface mobile.** Les boutons se chevauchent et le HUD est en pixels
  fixes : passer en tailles relatives (UIScale) avec des boutons placés.
- L'état de la vague n'est pas envoyé aux joueurs qui arrivent en cours de
  partie.
- Le radar ne montre pas les titans hors de portée : afficher des flèches
  au bord.

### P2
- Les crochets mordent l'eau.
- Aucun gaz égale aucun crochet : l'enfant reste coincé.
- La coupe propre est trop facile (la vitesse de chute compte).
- On peut farmer les chevilles et les yeux.
- La porte se répare sur les joueurs.
- Pas de recharge entre les manches.
- Pas de bord de map.
- Nuit longue.
- Accrocher un titan fait traverser son corps.

## 2. Map et performances

### P0
- **Bord de map.** Il y a des trous dans l'anneau de collines, et les
  joueurs tombent dans le vide. Ajouter une limite invisible et fermer les
  collines.
- **Terrain qui flotte au-dessus de la rivière.** Les bosses d'herbe sont
  ajoutées avant que la rivière soit creusée.
- **Streaming désactivé** avec 10 600 parts, sur une cible mobile.
- **352 lumières et feux s'allument d'un coup la nuit.** En réduire le
  nombre et n'allumer que celles proches du joueur sur mobile.

### P1
- La map est construite directement dans Workspace : la construire hors de
  Workspace et la parenter une seule fois.
- La construction du terrain est coûteuse (1M de voxels, ~2 100 FillBlock
  pour la rivière). Ajouter des mesures de temps.
- Arbres géants trop détaillés (19 parts) ; ombres et collisions activées
  sur les petites pièces (barrières, entretoises).
- 52 sapins sur 168 sont enterrés dans les collines.
- Une tour de signal a les pieds dans la colline du château.
- Des arbres, mannequins et maisons sont posés sur les routes. La route 3
  traverse le Terrain d'entraînement.
- Les bosses d'herbe recouvrent les routes ; la barrière coupe les
  carrefours.
- **Trous sans accroche.** 19,6 % du terrain est à plus de 170 studs d'un
  point d'accroche, surtout l'anneau extérieur et le nord-ouest. Il faut plus
  de bosquets et un anneau de tours.
- **Ravitaillement trop rare** sur la grande map : ajouter des caisses avec
  balise dans les bosquets et au nord.
- **Les titans traversent les décors et la colline du château.** Le château
  est une zone sûre permanente (le test de hauteur est absolu).
- Les titans ne vont jamais dans les nouvelles zones.
- Les titans apparaissent dans la forêt SE et dans les fermes.

### P2
- La route 3 traverse la rivière sans pont.
- La rivière passe en tunnel sous les collines.
- Pas de chemin pour monter au château.
- Des bosquets débordent sur les autres zones.
- Les plateformes des arbres traversent les branches.
- Les torches de la Grande Forêt sont au pied des arbres, pas sur les
  plateformes.
- Des chevauchements entre mannequins et arbres.
- Les coins du terrain ne sont pas arrondis.

## 3. Modèles et design des titans

### P0
- **L'uniforme en boîtes ne s'adapte pas aux avatars modernes** (Rthro,
  vêtements en couches, accessoires). Solution sans asset id :
  `GetAppliedDescription` puis retirer Shirt, Pants, les accessoires de dos
  et de taille et les corps Rthro, puis colorer le corps (veste, pantalon)
  et garder seulement les sangles, les bottes, la cape et l'équipement.

### P1 : technique
- Les titans vaincus sont entièrement ancrés : ils reviennent brusquement en
  pose de repos.
- La prise ne suit pas la main animée.
- La poignée des épées est mal placée en R6 : utiliser les GripAttachment.
- En R6, la cape traverse le boîtier ; les boîtes à lames touchent les mains.
- Les câbles partent du centre du corps, pas des lanceurs.
- **Les cheveux Cap et Mop et le casque de l'Armored couvrent le haut de la
  nuque.**
- Environ 22 % de parts en trop par titan (sourire, coins du torse, rotules
  cachées) et des ombres sur les petits détails.
- `GiantLook` ne permet pas de fixer la couleur de peau ou de cheveux : le
  Bestial peut être blond.

### P1 : design
- **Yeux qui suivent le joueur** (pupilles sur Motor6D) et clignements.
- **Le Briseur de mur** doit se lire de loin : peau de pierre avec fissures
  lumineuses, yeux luisants, vapeur, grosse mâchoire.
- **Le Bestial** doit faire singe : fourrure sombre, longs bras traînants,
  yeux luisants.
- **L'Armored** : plaques en plusieurs pièces, casque qui dégage les yeux,
  fissure lumineuse sur la nuque qui grandit à chaque coup.
- **Le Shifter** : visage héroïque, chignon, couleur selon le camp, vapeur.
- **Nouveaux titans** :
  - « Sprinteuse » agile qui protège sa nuque avec une main de cristal
    (attaque annoncée à l'avance) ;
  - « Rampant » à quatre pattes, avec la nuque facile à atteindre pour les
    débutants ;
  - variantes anormales : tête penchée, long cou, langue tirée.
- Vapeur sur les Colossaux.

### P2
- Plus de visages (moue, « oh », dents de lapin, sourcils), plus de
  coiffures (bol, mohawk, chignon, frisé), détails de peau, ventre seulement
  sur les gros, favoris mieux placés.
- Vue à la première personne (épées invisibles), épées qui touchent le sol
  en courant.

## Plan de correction

Trois agents travaillent en parallèle, chacun dans sa copie du dépôt avec
des fichiers séparés. Les résultats sont ensuite fusionnés et vérifiés :
types, mocks et rendus.

1. **Gameplay** (GrappleController, Hud, Radar, HunterService hors épées,
   GiantService, WaveService, ShifterService/Controller, CannonService,
   Main, nouveau DataService) : tous les P0 et P1 mécaniques, la sécurité, la
   défaite et la vie du district, le scaling, la sauvegarde, le tutoriel, le
   mobile, l'IA des titans dans la grande map.
2. **Map et performances** (World/*, MapBuilder, Geo, default.project.json) :
   bord de map, rivière, streaming, lumières, construction hors de
   Workspace, routes, accroches, caisses, spawns, nettoyage.
3. **Modèles** (GiantFactory, GiantAnimator, HunterGear, épées) : uniforme
   via HumanoidDescription, nuque dégagée, optimisation, yeux qui suivent,
   refonte du Briseur, du Bestial, de l'Armored et du Shifter, nouveaux
   titans Sprinteuse et Rampant, plus de visages et de coiffures.

## État après correction

Tout ce qui précède a été corrigé et fusionné dans `main` (gameplay
12456aa/e3fd894, map 3fd985d, modèles 0938693, intégration 22766d0). Seules
exceptions : les variantes anormales (tête penchée, long cou, langue).
Vérifié hors Studio : types luau-lsp sans erreur, `rojo build` OK, la map
complète se construit dans le mock, et les rigs de tous les titans sont sans
dérive ni pièce détachée.

**Reste à confirmer par un vrai test dans Studio :**
- le streaming ;
- la tenue via HumanoidDescription sur de vrais avatars ;
- le DataStore (activer l'accès API dans les paramètres du jeu) ;
- le placement des boutons tactiles ;
- le ressenti du grappin et de la prise ;
- le tutoriel ;
- l'équilibrage des vagues et de la vie du district.
