# Script de Presentation - Mini Projet AWS
## Duree totale : ~20 minutes
## Salim LAKHAL & Nossa IYAMU

---

## SLIDE 1 - Titre (~30 sec)

**[Salim ou Nossa]**

- Bonjour, nous sommes Salim LAKHAL et Nossa IYAMU
- Notre mini-projet : concevoir une application web hautement disponible et scalable sur AWS
- C'est dans le cadre du cours CSC 8604, Cloud Computing

---

## SLIDE 2 - Scenario (~2 min)

**[Presentateur 1]**

- Le contexte : l'Universite XYZ a une application web qui gere les dossiers etudiants
- Le probleme : pendant les periodes de pointe (admissions), l'application est **lente** voire **indisponible**
  - Trop de requetes simultanées, un seul serveur ne tient pas la charge
- A droite, vous voyez un apercu de l'application : c'est un simple CRUD
  - On peut voir la liste des etudiants, ajouter, modifier, supprimer
  - Chaque etudiant a un nom, adresse, ville, email et telephone
- **Notre mission** : migrer cette application vers AWS avec une architecture qui est :
  - Hautement disponible
  - Scalable automatiquement
  - Et securisee

---

## SLIDE 3 - Conditions requises (~1 min 30)

**[Presentateur 1]**

- L'architecture doit repondre a 6 exigences cles :
  - **Fonctionnelle** : les operations CRUD doivent marcher sans latence
  - **Charge equilibree** : le trafic doit etre reparti entre plusieurs serveurs
  - **Scalable** : l'infrastructure doit s'adapter automatiquement a la demande
  - **Hautement disponible** : si un serveur tombe, l'application continue de marcher
  - **Securisee** : la base de donnees isolee, les credentials pas en dur dans le code
  - **Couts optimises** : on utilise les plus petites instances possibles (t3.micro)

---

## SLIDE 4 - Approche par phases (~2 min 30)

**[Presentateur 2]**

- On a adopte une approche **incrementale** en 4 phases
  - Ca permet de partir simple et d'ajouter de la complexite progressivement
- **Phase 1** : Planification
  - On dessine l'architecture cible, on estime les couts avec AWS Pricing Calculator
- **Phase 2** : POC basique
  - On cree le VPC, on deploie tout sur un seul EC2 : Node.js ET MySQL sur la meme machine
  - Ca marche... mais tout est sur la meme machine avec les credentials en dur
- **Phase 3** : On decouple
  - On sort la BDD vers RDS dans un subnet prive
  - Les credentials passent dans Secrets Manager
- **Phase 4** : Haute disponibilite
  - On ajoute un Load Balancer, Auto Scaling Group
  - L'application devient vraiment resiliente

- En bas vous voyez la comparaison :
  - A gauche, la Phase 2 : tout sur une seule machine = **single point of failure**
  - A droite, la Phase 3-4 : architecture decouplee avec 2 AZs, RDS separe, Secrets Manager

---

## SLIDE 5 - Architecture finale (~3 min)

**[Presentateur 2]**

- Voici le schema de notre architecture finale, Phase 4
- On part de la gauche :
  - L'utilisateur accede via **Internet**
  - Le trafic passe par l'**Internet Gateway** du VPC
  - Il arrive sur l'**Application Load Balancer** qui ecoute sur le port 80
- L'ALB repartit le trafic entre **deux EC2** dans deux Availability Zones differentes
  - Elles sont gerees par un **Auto Scaling Group** (min 2, max 4, cible CPU 50%)
- Les EC2 se connectent a **Amazon RDS MySQL** dans les **subnets prives**
  - La BDD n'est **pas accessible depuis Internet**, uniquement depuis le Security Group des serveurs web
- Pour les credentials de connexion a la BDD :
  - Les EC2 utilisent leur **IAM Role** (LabInstanceProfile) pour interroger **Secrets Manager**
  - Le secret "Mydbsecret" contient host, user, password, database, port
  - Zero mot de passe en dur dans le code

---

## SLIDE 6 - Services AWS (~1 min 30)

**[Presentateur 1]**

- Recapitulatif des 8 services AWS utilises :
  - **VPC** avec Internet Gateway, 4 subnets (2 publics, 2 prives) et les Route Tables
  - **EC2** t3.micro sous Ubuntu pour le compute
  - **RDS** MySQL 8.0 db.t3.micro pour la base de donnees
  - **ALB** pour l'equilibrage de charge sur 2 AZs
  - **Auto Scaling** avec Target Tracking sur le CPU a 50%
  - **Secrets Manager** pour stocker les identifiants BDD de maniere securisee
  - **IAM** Role qui donne aux EC2 le droit de lire le secret
  - **Systems Manager** (SSM) pour administrer les instances sans SSH direct

---

## SLIDE 7 - Phase 1 & 2 : POC (~2 min)

**[Presentateur 1]**

- Phase 1 : on a dessine le schema architectural et estime les couts
- Phase 2 : on deploie un POC fonctionnel
  - On cree le VPC avec le CIDR 10.0.0.0/16
  - On lance un EC2 t3.micro dans le subnet public
  - On installe **tout** dessus : Node.js 18, Express, et MySQL
  - L'application CRUD est fonctionnelle et accessible via l'IP publique
- **A droite**, vous voyez le code de la Phase 2
  - Regardez la ligne surlignee : `password: 'student12'`
  - Le mot de passe est **en clair** directement dans le code
  - C'est une tres mauvaise pratique de securite
- Et en dessous les problemes :
  - Mot de passe en dur
  - Un seul serveur = si il tombe, plus d'application
  - BDD et app sur la meme machine = pas scalable separement

---

## SLIDE 8 - Phase 3 : Decouplage (~2 min)

**[Presentateur 2]**

- La Phase 3 est le grand changement : on decouple les composants
- Ce qu'on fait :
  - On ajoute des sous-reseaux prives dans 2 Availability Zones
  - On deploie **RDS MySQL** dans un DB Subnet Group sur ces subnets prives
  - On cree le secret "Mydbsecret" dans **AWS Secrets Manager** avec tous les identifiants
  - On attache le **IAM LabInstanceProfile** a l'EC2
  - Le Security Group de RDS n'accepte que le port 3306 depuis le SG du serveur web
- **A droite**, le code Phase 3-4 :
  - On importe le SDK AWS : `@aws-sdk/client-secrets-manager`
  - La fonction `getSecret()` va chercher les credentials au demarrage
  - Le `SecretsManagerClient` envoie une requete `GetSecretValue`
  - Le code recoit les credentials (host, user, password, database, port)
  - Et les utilise pour se connecter a RDS
- **Resultat** : zero credential en dur dans le code, c'est la best practice AWS

---

## SLIDE 9 - Phase 4 : HA et Scalabilite (~2 min)

**[Presentateur 2]**

- Phase 4 : on rend l'architecture hautement disponible et scalable
- **Application Load Balancer** :
  - Deploye sur les 2 AZs (us-east-1a et us-east-1b)
  - Il fait un health check sur '/' toutes les 30 secondes
  - Si un serveur ne repond plus, l'ALB arrete de lui envoyer du trafic
  - C'est le point d'entree unique pour les utilisateurs
- **EC2 Auto Scaling** :
  - On cree un Launch Template a partir d'une AMI pre-configuree
  - L'Auto Scaling Group demarre avec 2 instances minimum
  - Si le CPU moyen depasse 50%, il lance de nouvelles instances (jusqu'a 4 max)
  - Quand la charge redescend, il scale in automatiquement
- En bas vous voyez le schema du scaling :
  - Etat normal : 2 instances
  - Quand le CPU depasse 50% : 3 instances, puis 4 au maximum
- On a valide ca avec un **test de charge** utilisant loadtest depuis Cloud9

---

## SLIDE 10 - Securite (~1 min 30)

**[Presentateur 1]**

- La securite est au coeur de notre architecture
- En haut, la **chaine des Security Groups** :
  - Internet ne peut acceder qu'au port 80 de l'ALB
  - L'ALB forward sur le port 80 des serveurs web
  - Les serveurs web accedent a la BDD sur le port 3306
  - Chaque Security Group n'autorise que le SG precedent dans la chaine
- Trois piliers :
  - **Isolation reseau** : la BDD est dans des subnets prives, pas d'acces Internet direct
  - **Controle d'acces** : chaque SG n'ouvre que les ports necessaires
  - **Gestion des secrets** : Secrets Manager + IAM Role, zero credentials en dur

---

## SLIDE 11 - Estimation des couts (~1 min)

**[Presentateur 2]**

- L'estimation sur 12 mois en region us-east-1 :
  - EC2 : 2 instances t3.micro On-Demand = ~$184/an
  - RDS MySQL db.t3.micro avec 20 GB = ~$211/an
  - Le Load Balancer : ~$200/an
  - Secrets Manager : seulement ~$5/an
  - Data Transfer : ~$11/an
- **Total : environ $611 par an, soit $51 par mois**
- Et on peut optimiser davantage avec des **Reserved Instances** : -40%, ce qui donnerait ~$367/an

---

## SLIDE 12 - Demonstration (~3-4 min en live)

**[Les deux]**

- On va maintenant vous montrer l'application en live
- **Points a montrer pendant la demo** :
  1. Ouvrir l'URL du Load Balancer dans le navigateur
  2. Montrer la page d'accueil avec la liste des etudiants
  3. **Ajouter** un etudiant (remplir le formulaire)
  4. **Modifier** un etudiant existant
  5. **Supprimer** un etudiant
  6. (Si possible) Montrer la console AWS :
     - Le VPC avec les subnets
     - Les instances EC2 dans l'Auto Scaling Group
     - Le Load Balancer avec les target groups
     - Le secret dans Secrets Manager (sans reveler le contenu)
     - Le Security Group de RDS qui n'accepte que le SG du serveur web

---

## SLIDE 13 - Enseignements tires (~1 min 30)

**[Presentateur 1]**

- 5 enseignements cles :
  1. **Architecture par phases** : on ne construit pas tout d'un coup, on itere
  2. **Decouplage** : separer web et BDD permet de scaler chaque composant independamment
  3. **Secrets Manager** : ne jamais mettre les credentials en dur, c'est la base de la securite cloud
  4. **Auto Scaling + ALB** : la haute disponibilite devient automatique, pas besoin d'intervention manuelle
  5. **Gestion des couts** : surveiller le budget, utiliser les bonnes tailles d'instances
- Et pour aller plus loin :
  - Ajouter HTTPS avec un certificat SSL via ACM
  - Multi-AZ sur RDS pour la haute dispo de la base aussi
  - CloudFront pour les assets statiques
  - Authentification utilisateur avec Amazon Cognito

---

## SLIDE 14 - Merci (~30 sec)

**[Les deux]**

- Merci pour votre attention
- On est prets pour vos questions

---

## Repartition suggeree entre presentateurs

| Slides | Presentateur | Duree |
|--------|-------------|-------|
| 1 (Titre) | Ensemble | 30 sec |
| 2, 3 (Scenario, Conditions) | Presentateur 1 | 3 min 30 |
| 4, 5 (Phases, Architecture) | Presentateur 2 | 5 min 30 |
| 6, 7 (Services, Phase 1-2) | Presentateur 1 | 3 min 30 |
| 8, 9 (Phase 3, Phase 4) | Presentateur 2 | 4 min |
| 10 (Securite) | Presentateur 1 | 1 min 30 |
| 11 (Couts) | Presentateur 2 | 1 min |
| 12 (Demo) | Ensemble | 3-4 min |
| 13 (Enseignements) | Presentateur 1 | 1 min 30 |
| 14 (Merci) | Ensemble | 30 sec |

**Total : ~19-20 minutes** (hors questions)

---

## Tips pour le jour J

- **Parler lentement** et clairement, pas besoin de se presser
- Sur le slide d'architecture (slide 5), **pointer les elements** en decrivant le flux de gauche a droite
- Sur les slides de code (slides 7, 8), bien **montrer la difference** entre les deux versions
- Pendant la demo, avoir l'URL du ALB prete dans un onglet
- Si la demo ne marche pas (toujours avoir un plan B) : montrer des screenshots
