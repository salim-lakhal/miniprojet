# Mini-Projet AWS — Application Web Student CRUD

## Description
Application web Node.js (Express + EJS + MySQL) deployee sur AWS avec une architecture securisee : VPC, EC2, RDS, IAM, Secrets Manager.

## Architecture
- **EC2** (subnet public) — Serveur Node.js avec Express
- **RDS MySQL** (subnet prive) — Base de donnees geree
- **Secrets Manager** — Stockage securise des credentials BDD
- **IAM Role** — Permissions EC2 vers Secrets Manager
- **Security Groups** — Chainage SG web → SG BDD

## Structure du repo

```
code/              # Code source de l'application
  phase2/          # Version locale (MySQL sur EC2)
  phase3-4/        # Version AWS (RDS + Secrets Manager)
docs/              # Livrables PDF
  Rapport-MiniProjet.pdf
  Guide-Code-Demo.pdf
  MiniProjet-Presentation.pdf
  architecture-diagram.html   # Diagrammes Mermaid.js (ouvrir dans un navigateur)
scripts/           # Scripts de deploiement EC2 User Data
revision/          # Fiches de revision et QCM d'entrainement
```

## Stack technique
- Node.js + Express + EJS
- MySQL (RDS)
- AWS SDK (Secrets Manager)
- systemd (service auto-restart)
