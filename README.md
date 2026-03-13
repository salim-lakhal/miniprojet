# Mini-Projet AWS — Application Web Student CRUD

## C'est quoi ce projet ?

Une application web qui permet de **gerer une liste d'etudiants** (ajouter, modifier, supprimer, afficher). L'objectif est de la deployer sur **Amazon Web Services (AWS)** avec une architecture cloud securisee et professionnelle.

## Le projet en 4 phases

### Phase 1 — Creer le reseau (VPC)

On commence par construire le **reseau prive virtuel** dans AWS :

1. Creer un **VPC** avec le CIDR `10.0.0.0/16` (notre reseau isole)
2. Creer un **subnet public** (pour le serveur web — accessible depuis Internet)
3. Creer un **subnet prive** (pour la base de donnees — PAS accessible depuis Internet)
4. Creer un **Internet Gateway** et l'attacher au VPC (c'est la porte vers Internet)
5. Configurer les **Route Tables** :
   - Subnet public : `0.0.0.0/0 → Internet Gateway` (le trafic sort vers Internet)
   - Subnet prive : pas de route vers Internet (isole)

**Resultat :** un reseau avec une zone publique et une zone privee, comme un immeuble avec des etages accessibles au public et des etages prives.

### Phase 2 — Deployer l'app en local sur EC2

On deploie une premiere version simple :

1. Lancer une **instance EC2** (t2.micro) dans le subnet public
2. Installer **Node.js** et **MySQL** directement sur cette instance
3. Deployer l'application Express.js qui fait le CRUD (Create, Read, Update, Delete)
4. L'app tourne sur le **port 80** et est accessible via l'IP publique de l'EC2

**Le probleme :** tout est sur la meme machine (app + BDD), le mot de passe MySQL est en dur dans le code, et si l'EC2 tombe, on perd tout.

### Phase 3 — Migrer la BDD vers RDS

On separe la base de donnees pour plus de securite et de fiabilite :

1. Creer une instance **RDS MySQL** dans le **subnet prive**
2. Configurer le **Security Group de RDS** : port 3306 ouvert **uniquement depuis le SG de l'EC2** (chainage de SG)
3. Stocker les credentials de la BDD dans **AWS Secrets Manager** (plus de mot de passe en dur !)
4. Attacher un **IAM Role** a l'EC2 pour qu'elle puisse lire le secret
5. Modifier le code de l'app pour recuperer les credentials depuis Secrets Manager au demarrage

**Resultat :** la BDD est isolee dans un subnet prive, les credentials sont securises, et l'EC2 accede a la BDD via son IAM Role.

### Phase 4 — Securiser et finaliser

On ajoute les bonnes pratiques :

1. **Security Group EC2** : port 80 (HTTP) ouvert a tous, port 22 (SSH) ouvert a mon IP seulement
2. **Security Group RDS** : port 3306 ouvert uniquement depuis le SG de l'EC2
3. Configurer un **service systemd** pour que l'app redemarre automatiquement si elle crash
4. Activer **Multi-AZ** sur RDS pour la haute disponibilite
5. Verifier que la BDD n'est **pas accessible depuis Internet**

## Architecture finale

```
                    Internet
                       |
                Internet Gateway
                       |
              +--------+--------+
              |    VPC 10.0.0.0/16    |
              |                       |
    +---------+--------+   +----------+---------+
    |   Subnet Public  |   |   Subnet Prive     |
    |                  |   |                     |
    |   EC2 (Node.js)  |   |   RDS MySQL         |
    |   Port 80, 22    |   |   Port 3306          |
    |   SG: web-sg     |---|   SG: db-sg          |
    +------------------+   |   (accepte web-sg)   |
              |            +---------------------+
              |
        IAM Role ──> Secrets Manager
                     (credentials BDD)
```

**Flux de l'application :**
1. L'utilisateur accede au site via l'IP publique de l'EC2 (port 80)
2. L'app Node.js demarre et recupere les credentials BDD depuis **Secrets Manager**
3. L'app se connecte a **RDS MySQL** dans le subnet prive
4. L'utilisateur peut ajouter/modifier/supprimer des etudiants (CRUD)

## Le code

### Phase 2 (`code/phase2/`)
- `app.js` — Serveur Express avec MySQL local, credentials en dur
- `setup-db.sql` — Script SQL pour creer la BDD, la table et l'utilisateur
- `views/` — Templates EJS (index, add, edit)

### Phase 3-4 (`code/phase3-4/`)
- `app.js` — Serveur Express avec **RDS via Secrets Manager** (credentials recuperes au runtime)
- `student-app.service` — Fichier systemd pour que l'app tourne en service et redemarre auto
- `views/` — Memes templates EJS

**Difference cle entre phase2 et phase3-4 :** dans phase2, le mot de passe est ecrit dans le code. Dans phase3-4, l'app utilise le SDK AWS pour aller chercher les credentials dans Secrets Manager au demarrage.

## Stack technique

| Composant | Technologie |
|-----------|------------|
| Backend | Node.js + Express |
| Templates | EJS |
| Base de donnees | MySQL (RDS) |
| Credentials | AWS Secrets Manager + AWS SDK |
| Deploiement | EC2 User Data + systemd |
| Reseau | VPC, subnets, IGW, Security Groups |
| Permissions | IAM Role |

## Structure du repo

```
README.md              # Ce fichier
code/
  phase2/              # Version locale (MySQL sur EC2, credentials en dur)
  phase3-4/            # Version AWS (RDS + Secrets Manager)
docs/
  Rapport-MiniProjet.pdf          # Rapport complet du projet
  Guide-Code-Demo.pdf             # Guide du code + instructions de demo
  MiniProjet-Presentation.pdf     # Slides de presentation
  DescriptionMiniProjet.pdf       # Consignes du prof
  architecture-diagram.html       # Diagrammes interactifs (ouvrir dans un navigateur)
scripts/
  appserver-userdata.sh           # Script User Data pour deployer l'app sur EC2
  poc-userdata.sh                 # Script User Data pour la phase 2 (POC)
revision/
  Revision-Exam-CSC8604.pdf       # Fiche de revision complete (17 sections)
  QCM-Training-Exam.pdf           # 80 questions d'entrainement avec corrections
```

## Services AWS utilises

| Service | Role dans le projet |
|---------|-------------------|
| **VPC** | Reseau prive isole |
| **EC2** | Serveur qui heberge l'application Node.js |
| **RDS** | Base de donnees MySQL geree par AWS |
| **Secrets Manager** | Stockage securise du mot de passe de la BDD |
| **IAM** | Role qui donne a l'EC2 le droit de lire les secrets |
| **Security Groups** | Firewall virtuel (port 80 pour le web, 3306 pour la BDD) |
