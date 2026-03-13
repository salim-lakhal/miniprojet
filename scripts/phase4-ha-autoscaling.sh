#!/bin/bash
# =============================================================================
# PHASE 4 - HAUTE DISPONIBILITE ET MISE A L'ECHELLE (AUTO SCALING)
# =============================================================================
# Projet : Application CRUD Node.js sur AWS
# Phase   : 4 - Mise en oeuvre de la haute disponibilité et de la capacité
#           de mise à l'échelle élevée
#
# Ce script est un DOCUMENT DE REFERENCE - il n'est pas conçu pour être
# exécuté en une seule fois. Chaque section doit être exécutée manuellement
# après avoir remplacé les valeurs entre chevrons (<...>) par les valeurs
# réelles de votre environnement.
#
# Architecture cible :
#   Internet → ALB (subnets publics, 2 AZ) → ASG (2-6 EC2) → RDS MySQL
#
# Prérequis :
#   - Phase 1 complétée : VPC, subnets, Security Groups
#   - Phase 2 complétée : EC2 avec l'application Node.js fonctionnelle
#   - Phase 3 complétée : RDS MySQL, Secrets Manager
#   - AWS CLI configuré avec les bonnes permissions
#   - Une AMI créée à partir de l'instance EC2 de la phase 2
# =============================================================================

# ---------------------------------------------------------------------------
# VARIABLES DE CONFIGURATION - A REMPLACER PAR VOS VALEURS
# ---------------------------------------------------------------------------

# Réseau
VPC_ID="<YOUR-VPC-ID>"                        # ex: vpc-0abc123def456789
SUBNET_PUBLIC_1="<YOUR-SUBNET-PUBLIC-1>"      # ex: subnet-0abc123def456789 (AZ-a)
SUBNET_PUBLIC_2="<YOUR-SUBNET-PUBLIC-2>"      # ex: subnet-0def456abc789012 (AZ-b)
SUBNET_PRIVATE_1="<YOUR-SUBNET-PRIVATE-1>"    # ex: subnet-0789012abc123def (AZ-a, pour ASG si souhaité)
SUBNET_PRIVATE_2="<YOUR-SUBNET-PRIVATE-2>"    # ex: subnet-0012def789456abc (AZ-b, pour ASG si souhaité)

# Security Groups (créés en Phase 1)
WEB_SG_ID="<YOUR-WEB-SG-ID>"                 # ex: sg-0abc123def456789 (autorise port 80/443)
ALB_SG_ID="<YOUR-ALB-SG-ID>"                 # ex: sg-0def456abc789012 (SG dédié à l'ALB, optionnel)
# Note : si vous n'avez pas de SG dédié à l'ALB, créez-en un (voir section ALB)

# AMI de l'instance EC2 de la phase 2 (avec l'application déjà installée)
APP_AMI_ID="<YOUR-APP-AMI-ID>"               # ex: ami-0abc123def456789

# Type d'instance pour les EC2 du groupe Auto Scaling
INSTANCE_TYPE="t2.micro"                      # Ajuster selon les besoins

# Paire de clés SSH
KEY_PAIR_NAME="<YOUR-KEY-PAIR-NAME>"          # ex: vockey

# ARN du secret Secrets Manager (créé en Phase 3)
SECRET_ARN="<YOUR-SECRET-ARN>"               # ex: arn:aws:secretsmanager:us-east-1:123456789012:secret:db-credentials-xxxxx

# Region AWS
AWS_REGION="us-east-1"                       # Adapter si nécessaire

# Tags communs
PROJECT_TAG="miniprojet"
OWNER_TAG="<YOUR-NAME>"

# ---------------------------------------------------------------------------
# TACHE 1 : CREATION DE L'APPLICATION LOAD BALANCER (ALB)
# ---------------------------------------------------------------------------
# L'ALB distribue le trafic entrant sur les instances EC2 du groupe Auto
# Scaling. Il est déployé dans les subnets PUBLICS pour être accessible
# depuis Internet.
#
# Composants créés :
#   1. Security Group pour l'ALB (si pas encore fait)
#   2. Target Group (groupe cible qui reçoit le trafic)
#   3. Application Load Balancer
#   4. Listener HTTP sur le port 80

echo "=== TACHE 1 : Application Load Balancer ==="

# ---- 1.1 (Optionnel) Créer un Security Group dédié à l'ALB ----
# Bonne pratique : un SG distinct pour l'ALB permet de contrôler finement
# le trafic. Le SG de l'EC2 (web-sg) n'autorisera alors le port 80 que
# depuis ce SG ALB (et non depuis Internet directement).

aws ec2 create-security-group \
  --group-name "alb-sg" \
  --description "Security Group pour l'Application Load Balancer" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=alb-sg},{Key=Project,Value=$PROJECT_TAG}]" \
  --region "$AWS_REGION"
# => Notez le GroupId retourné et affectez-le à ALB_SG_ID ci-dessus

# Autoriser le trafic HTTP entrant (port 80) depuis Internet vers l'ALB
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION"

# Autoriser le trafic HTTPS entrant (port 443) depuis Internet vers l'ALB
# (à activer si vous configurez un certificat SSL/TLS)
# aws ec2 authorize-security-group-ingress \
#   --group-id "$ALB_SG_ID" \
#   --protocol tcp \
#   --port 443 \
#   --cidr 0.0.0.0/0 \
#   --region "$AWS_REGION"

# Mettre à jour le SG des EC2 pour n'accepter le port 80 que depuis l'ALB
# (remplacer la règle existante "0.0.0.0/0" par une règle source SG ALB)
aws ec2 authorize-security-group-ingress \
  --group-id "$WEB_SG_ID" \
  --protocol tcp \
  --port 80 \
  --source-group "$ALB_SG_ID" \
  --region "$AWS_REGION"

# ---- 1.2 Créer le Target Group ----
# Le Target Group définit comment l'ALB achemine les requêtes vers les
# instances EC2. Le health check vérifie que l'application répond correctement.

aws elbv2 create-target-group \
  --name "nodejs-app-tg" \
  --protocol HTTP \
  --port 80 \
  --vpc-id "$VPC_ID" \
  --target-type instance \
  --health-check-protocol HTTP \
  --health-check-path "/" \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --matcher "HttpCode=200" \
  --tags "Key=Name,Value=nodejs-app-tg" "Key=Project,Value=$PROJECT_TAG" \
  --region "$AWS_REGION"
# => Notez le TargetGroupArn retourné
# Exemple de sortie :
# {
#   "TargetGroups": [{
#     "TargetGroupArn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/nodejs-app-tg/abc123def456",
#     ...
#   }]
# }

TARGET_GROUP_ARN="<TARGET-GROUP-ARN>"        # Remplacer par l'ARN obtenu ci-dessus

# ---- 1.3 Créer l'Application Load Balancer ----
# L'ALB est déployé dans les deux subnets PUBLICS pour la haute disponibilité
# sur deux zones de disponibilité.

aws elbv2 create-load-balancer \
  --name "nodejs-app-alb" \
  --subnets "$SUBNET_PUBLIC_1" "$SUBNET_PUBLIC_2" \
  --security-groups "$ALB_SG_ID" \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --tags "Key=Name,Value=nodejs-app-alb" "Key=Project,Value=$PROJECT_TAG" \
  --region "$AWS_REGION"
# => Notez le LoadBalancerArn et le DNSName retournés
# Exemple de sortie :
# {
#   "LoadBalancers": [{
#     "LoadBalancerArn": "arn:aws:elasticloadbalancing:us-east-1:...",
#     "DNSName": "nodejs-app-alb-1234567890.us-east-1.elb.amazonaws.com",
#     ...
#   }]
# }

ALB_ARN="<ALB-ARN>"                          # Remplacer par l'ARN obtenu ci-dessus
ALB_DNS="<ALB-DNS-NAME>"                     # Remplacer par le DNSName obtenu ci-dessus

# ---- 1.4 Créer le Listener HTTP (port 80) ----
# Le listener écoute sur le port 80 et transfère les requêtes au Target Group.

aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$TARGET_GROUP_ARN" \
  --tags "Key=Name,Value=nodejs-app-listener-http" "Key=Project,Value=$PROJECT_TAG" \
  --region "$AWS_REGION"

# ---- Vérifications ----
# Vérifier que l'ALB est en état "active"
aws elbv2 describe-load-balancers \
  --names "nodejs-app-alb" \
  --query "LoadBalancers[0].{State:State.Code,DNSName:DNSName}" \
  --output table \
  --region "$AWS_REGION"

# Vérifier le Target Group
aws elbv2 describe-target-groups \
  --names "nodejs-app-tg" \
  --query "TargetGroups[0].{ARN:TargetGroupArn,Protocol:Protocol,Port:Port,HealthCheck:HealthCheckPath}" \
  --output table \
  --region "$AWS_REGION"

# ---------------------------------------------------------------------------
# TACHE 2 : AUTO SCALING EC2
# ---------------------------------------------------------------------------
# L'Auto Scaling Group (ASG) gère automatiquement le nombre d'instances EC2
# en fonction de la charge. Il garantit qu'un minimum de 2 instances tournent
# en permanence (une par AZ) pour la haute disponibilité.
#
# Composants créés :
#   1. Launch Template (modèle de lancement des instances)
#   2. Auto Scaling Group
#   3. Scaling Policies (politiques de mise à l'échelle)

echo "=== TACHE 2 : Auto Scaling Group ==="

# ---- 2.1 Créer le Launch Template ----
# Le Launch Template définit la configuration de chaque nouvelle instance
# EC2 créée par l'ASG : AMI, type, réseau, User Data, etc.
#
# IMPORTANT : L'AMI utilisée doit être créée à partir de l'instance EC2
# de la phase 2, avec l'application Node.js déjà installée et configurée.
# Pour créer une AMI depuis une instance existante :
#   aws ec2 create-image \
#     --instance-id <INSTANCE-ID-PHASE2> \
#     --name "nodejs-app-ami-$(date +%Y%m%d)" \
#     --description "AMI avec application Node.js CRUD" \
#     --no-reboot \
#     --region "$AWS_REGION"

# User Data : script exécuté au démarrage de chaque nouvelle instance
# Ce script démarre l'application si elle n'est pas déjà démarrée au boot.
# Adapter selon votre installation (pm2, systemd, etc.)
cat > /tmp/user-data.sh << 'USERDATA'
#!/bin/bash
# Démarrage automatique de l'application Node.js au boot
# Si pm2 est installé et configuré pour démarrer au boot, ce bloc peut
# être simplifié ou supprimé.

# Vérifier que l'application tourne (si pm2 est utilisé)
if command -v pm2 &> /dev/null; then
  pm2 resurrect || pm2 start /home/ec2-user/app/index.js --name "nodejs-app"
  pm2 save
else
  # Démarrage direct avec node (non recommandé en production)
  cd /home/ec2-user/app && node index.js &
fi
USERDATA

# Encoder le User Data en base64
USER_DATA_B64=$(base64 -w 0 /tmp/user-data.sh)

# Créer le Launch Template
aws ec2 create-launch-template \
  --launch-template-name "nodejs-app-lt" \
  --version-description "Version initiale - Phase 4" \
  --launch-template-data "{
    \"ImageId\": \"$APP_AMI_ID\",
    \"InstanceType\": \"$INSTANCE_TYPE\",
    \"KeyName\": \"$KEY_PAIR_NAME\",
    \"SecurityGroupIds\": [\"$WEB_SG_ID\"],
    \"UserData\": \"$USER_DATA_B64\",
    \"IamInstanceProfile\": {
      \"Name\": \"<YOUR-INSTANCE-PROFILE-NAME>\"
    },
    \"Monitoring\": {
      \"Enabled\": true
    },
    \"TagSpecifications\": [
      {
        \"ResourceType\": \"instance\",
        \"Tags\": [
          {\"Key\": \"Name\", \"Value\": \"nodejs-app-asg-instance\"},
          {\"Key\": \"Project\", \"Value\": \"$PROJECT_TAG\"},
          {\"Key\": \"ManagedBy\", \"Value\": \"AutoScaling\"}
        ]
      }
    ]
  }" \
  --tag-specifications "ResourceType=launch-template,Tags=[{Key=Name,Value=nodejs-app-lt},{Key=Project,Value=$PROJECT_TAG}]" \
  --region "$AWS_REGION"
# => Notez le LaunchTemplateId et la Version retournés

LAUNCH_TEMPLATE_ID="<LAUNCH-TEMPLATE-ID>"   # Remplacer par l'ID obtenu ci-dessus

# ---- 2.2 Créer l'Auto Scaling Group ----
# L'ASG déploie les instances dans les subnets PUBLICS (ou privés selon
# l'architecture). Avec min=2 et desired=2, une instance est déployée
# dans chaque AZ dès la création.
#
# Note sur le choix des subnets :
#   - Subnets PUBLICS : les instances ont une IP publique (utile pour debug SSH)
#   - Subnets PRIVÉS  : les instances n'ont pas d'IP publique (recommandé en
#     production - l'ALB route le trafic depuis les subnets publics vers les
#     instances privées via le Target Group)

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "nodejs-app-asg" \
  --launch-template "LaunchTemplateId=$LAUNCH_TEMPLATE_ID,Version=\$Latest" \
  --min-size 2 \
  --max-size 6 \
  --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_PUBLIC_1,$SUBNET_PUBLIC_2" \
  --target-group-arns "$TARGET_GROUP_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 300 \
  --default-cooldown 300 \
  --tags \
    "Key=Name,Value=nodejs-app-asg-instance,PropagateAtLaunch=true" \
    "Key=Project,Value=$PROJECT_TAG,PropagateAtLaunch=true" \
    "Key=ManagedBy,Value=AutoScaling,PropagateAtLaunch=true" \
  --region "$AWS_REGION"
# Paramètres clés :
#   --min-size 2           : toujours au moins 2 instances (1 par AZ)
#   --max-size 6           : jamais plus de 6 instances (contrôle des coûts)
#   --desired-capacity 2   : état initial souhaité
#   --health-check-type ELB: utilise les health checks de l'ALB (plus précis
#                            que les checks EC2 seuls)
#   --health-check-grace-period 300 : laisse 5 min au démarrage avant de
#                            considérer l'instance comme unhealthy
#   --default-cooldown 300 : attente de 5 min entre deux actions de scaling
#                            pour éviter les oscillations

# ---- 2.3 Créer la Scaling Policy - Target Tracking (CPU 50%) ----
# La politique Target Tracking ajuste automatiquement le nombre d'instances
# pour maintenir l'utilisation CPU à 50% en moyenne.
# AWS calcule automatiquement les seuils scale-out et scale-in.

aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "nodejs-app-asg" \
  --policy-name "nodejs-app-cpu-target-tracking" \
  --policy-type "TargetTrackingScaling" \
  --target-tracking-configuration "{
    \"PredefinedMetricSpecification\": {
      \"PredefinedMetricType\": \"ASGAverageCPUUtilization\"
    },
    \"TargetValue\": 50.0,
    \"DisableScaleIn\": false
  }" \
  --region "$AWS_REGION"
# => TargetValue 50.0 : l'ASG ajuste le nombre d'instances pour que
#    l'utilisation CPU moyenne reste autour de 50%
# => DisableScaleIn false : autorise la réduction du nombre d'instances
#    quand la charge diminue (économie de coûts)

# ---- 2.4 (Optionnel) Scaling Policies supplémentaires ----
# Politique de montée en charge rapide sur pic CPU (Step Scaling)
# Utile si vous souhaitez un comportement plus agressif en scale-out.

# Scale-Out : ajouter 2 instances si CPU > 70% pendant 2 minutes
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "nodejs-app-asg" \
  --policy-name "nodejs-app-scale-out-step" \
  --policy-type "StepScaling" \
  --adjustment-type "ChangeInCapacity" \
  --step-adjustments \
    "MetricIntervalLowerBound=0,MetricIntervalUpperBound=20,ScalingAdjustment=1" \
    "MetricIntervalLowerBound=20,ScalingAdjustment=2" \
  --metric-aggregation-type "Average" \
  --region "$AWS_REGION"

# Créer l'alarme CloudWatch déclenchant le scale-out
SCALE_OUT_POLICY_ARN="<SCALE-OUT-POLICY-ARN>"  # ARN retourné par la commande précédente

aws cloudwatch put-metric-alarm \
  --alarm-name "nodejs-app-high-cpu" \
  --alarm-description "CPU > 70% - Scale Out ASG" \
  --metric-name "CPUUtilization" \
  --namespace "AWS/EC2" \
  --statistic "Average" \
  --period 120 \
  --evaluation-periods 2 \
  --threshold 70 \
  --comparison-operator "GreaterThanThreshold" \
  --dimensions "Name=AutoScalingGroupName,Value=nodejs-app-asg" \
  --alarm-actions "$SCALE_OUT_POLICY_ARN" \
  --treat-missing-data "notBreaching" \
  --region "$AWS_REGION"

# Scale-In : retirer 1 instance si CPU < 25% pendant 5 minutes
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "nodejs-app-asg" \
  --policy-name "nodejs-app-scale-in-step" \
  --policy-type "StepScaling" \
  --adjustment-type "ChangeInCapacity" \
  --step-adjustments "MetricIntervalUpperBound=0,ScalingAdjustment=-1" \
  --metric-aggregation-type "Average" \
  --region "$AWS_REGION"

SCALE_IN_POLICY_ARN="<SCALE-IN-POLICY-ARN>"    # ARN retourné par la commande précédente

aws cloudwatch put-metric-alarm \
  --alarm-name "nodejs-app-low-cpu" \
  --alarm-description "CPU < 25% - Scale In ASG" \
  --metric-name "CPUUtilization" \
  --namespace "AWS/EC2" \
  --statistic "Average" \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 25 \
  --comparison-operator "LessThanThreshold" \
  --dimensions "Name=AutoScalingGroupName,Value=nodejs-app-asg" \
  --alarm-actions "$SCALE_IN_POLICY_ARN" \
  --treat-missing-data "notBreaching" \
  --region "$AWS_REGION"

# ---- Vérifications ----
# Vérifier l'état de l'ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "nodejs-app-asg" \
  --query "AutoScalingGroups[0].{
    Min:MinSize,
    Max:MaxSize,
    Desired:DesiredCapacity,
    Instances:Instances[*].{ID:InstanceId,AZ:AvailabilityZone,Health:HealthStatus,State:LifecycleState}
  }" \
  --output json \
  --region "$AWS_REGION"

# Vérifier l'état des instances dans le Target Group
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --query "TargetHealthDescriptions[*].{InstanceId:Target.Id,Port:Target.Port,State:TargetHealth.State,Description:TargetHealth.Description}" \
  --output table \
  --region "$AWS_REGION"

# Vérifier les politiques de scaling
aws autoscaling describe-policies \
  --auto-scaling-group-name "nodejs-app-asg" \
  --query "ScalingPolicies[*].{Name:PolicyName,Type:PolicyType,Status:Enabled}" \
  --output table \
  --region "$AWS_REGION"

# ---------------------------------------------------------------------------
# TACHE 3 : ACCEDER A L'APPLICATION VIA L'ALB
# ---------------------------------------------------------------------------
# Une fois l'ALB actif et les instances enregistrées et saines dans le
# Target Group, l'application est accessible via le DNS de l'ALB.

echo "=== TACHE 3 : Accès à l'application ==="

# Récupérer le DNS de l'ALB
aws elbv2 describe-load-balancers \
  --names "nodejs-app-alb" \
  --query "LoadBalancers[0].DNSName" \
  --output text \
  --region "$AWS_REGION"
# => Retourne quelque chose comme :
#    nodejs-app-alb-1234567890.us-east-1.elb.amazonaws.com

# Tester l'accès HTTP à l'application
# curl http://<ALB-DNS-NAME>/
# curl http://<ALB-DNS-NAME>/api/items      # Exemple d'endpoint CRUD

# Vérifier les logs d'accès ALB (si activés dans S3) :
# aws s3 ls s3://<YOUR-ALB-LOGS-BUCKET>/AWSLogs/<ACCOUNT-ID>/elasticloadbalancing/

# Attendre que le Target Group soit healthy (polling manuel ou script)
echo "Attendre que les instances soient 'healthy' dans le Target Group..."
echo "Commande de vérification :"
echo "  aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN --region $AWS_REGION"
echo ""
echo "URL d'accès à l'application : http://$ALB_DNS"

# ---------------------------------------------------------------------------
# TACHE 4 : TESTS DE CHARGE ET DECLENCHEMENT DU SCALING
# ---------------------------------------------------------------------------
# Pour vérifier que l'Auto Scaling fonctionne correctement, on génère une
# charge artificielle sur les instances EC2 via l'ALB.
#
# Deux méthodes présentées :
#   A. stress : génère une charge CPU directement sur l'instance (via SSH)
#   B. ab (Apache Bench) : génère des requêtes HTTP via l'ALB

echo "=== TACHE 4 : Tests de charge ==="

# ---- Méthode A : stress (charge CPU directe sur une instance) ----
# Prérequis : accès SSH à une instance de l'ASG
# Installer stress si absent : sudo yum install -y stress (Amazon Linux)
#                              sudo apt-get install -y stress (Ubuntu)

# Se connecter à une instance (récupérer l'IP publique ou utiliser SSM)
INSTANCE_ID_1="<INSTANCE-ID-FROM-ASG>"       # Une instance de l'ASG

# Option 1 : SSH direct (si IP publique assignée et port 22 ouvert)
# ssh -i ~/.ssh/<KEY-PAIR>.pem ec2-user@<INSTANCE-PUBLIC-IP>

# Option 2 : AWS Systems Manager Session Manager (pas besoin de port 22)
# aws ssm start-session --target "$INSTANCE_ID_1" --region "$AWS_REGION"

# Sur l'instance (une fois connecté), générer de la charge CPU :
# sudo stress --cpu 4 --timeout 300
# Explication :
#   --cpu 4      : 4 workers consommant 100% CPU chacun
#   --timeout 300: durée de 5 minutes (300 secondes)

# Surveiller le scaling en temps réel (depuis votre terminal local) :
# watch -n 30 "aws autoscaling describe-auto-scaling-groups \
#   --auto-scaling-group-names nodejs-app-asg \
#   --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Count:length(Instances)}' \
#   --output table --region $AWS_REGION"

# ---- Méthode B : Apache Bench (charge HTTP via l'ALB) ----
# Prérequis : ab installé (yum install -y httpd-tools / apt install apache2-utils)
# Depuis votre machine locale ou une instance EC2 dans le VPC :

ALB_URL="http://$ALB_DNS/"

# Test de base : 1000 requêtes, 50 connexions concurrentes
# ab -n 1000 -c 50 "$ALB_URL"

# Test de charge prolongé : 100 000 requêtes, 200 connexions concurrentes, timeout 30s
# ab -n 100000 -c 200 -t 300 -k "$ALB_URL"
# Explication :
#   -n 100000  : nombre total de requêtes
#   -c 200     : requêtes concurrentes simultanées
#   -t 300     : durée maximale en secondes (5 minutes)
#   -k         : keep-alive HTTP (plus réaliste)

# ---- Méthode C : wrk (outil de charge HTTP haute performance) ----
# Installation : voir https://github.com/wg/wrk
# wrk -t 12 -c 400 -d 300s "$ALB_URL"
# Explication :
#   -t 12   : 12 threads
#   -c 400  : 400 connexions ouvertes
#   -d 300s : durée 5 minutes

# ---- Surveillance pendant le test de charge ----
# 1. Métriques CPU via CloudWatch (console AWS ou CLI)
aws cloudwatch get-metric-statistics \
  --metric-name "CPUUtilization" \
  --namespace "AWS/EC2" \
  --dimensions "Name=AutoScalingGroupName,Value=nodejs-app-asg" \
  --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics "Average" "Maximum" \
  --query "Datapoints[*].{Time:Timestamp,Avg:Average,Max:Maximum}" \
  --output table \
  --region "$AWS_REGION"

# 2. Historique des activités de scaling
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "nodejs-app-asg" \
  --max-items 10 \
  --query "Activities[*].{Status:StatusCode,Start:StartTime,Description:Description}" \
  --output table \
  --region "$AWS_REGION"

# 3. État actuel de l'ASG (nombre d'instances)
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "nodejs-app-asg" \
  --query "AutoScalingGroups[0].{Desired:DesiredCapacity,Running:length(Instances[?LifecycleState=='InService'])}" \
  --output table \
  --region "$AWS_REGION"

# 4. Métriques de l'ALB (requêtes, temps de réponse, erreurs)
aws cloudwatch get-metric-statistics \
  --metric-name "RequestCount" \
  --namespace "AWS/ApplicationELB" \
  --dimensions "Name=LoadBalancer,Value=<ALB-DIMENSION-VALUE>" \
  --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics "Sum" \
  --output table \
  --region "$AWS_REGION"
# Note : <ALB-DIMENSION-VALUE> est la valeur du LoadBalancer dans les dimensions
# CloudWatch. Format : app/<ALB-NAME>/<ID>
# Récupérer avec :
# aws elbv2 describe-load-balancers --names nodejs-app-alb \
#   --query "LoadBalancers[0].LoadBalancerArn" --output text | \
#   sed 's|arn:aws:elasticloadbalancing:[^:]*:[^:]*:loadbalancer/||'

# ---------------------------------------------------------------------------
# NETTOYAGE (optionnel - a la fin des tests)
# ---------------------------------------------------------------------------
# ATTENTION : Ces commandes suppriment toutes les ressources créées dans
# cette phase. A exécuter uniquement si vous souhaitez nettoyer l'environnement.

echo "=== NETTOYAGE (optionnel) ==="

# Ordre de suppression (respecter les dépendances) :

# 1. Supprimer les alarmes CloudWatch
# aws cloudwatch delete-alarms \
#   --alarm-names "nodejs-app-high-cpu" "nodejs-app-low-cpu" \
#   --region "$AWS_REGION"

# 2. Supprimer l'Auto Scaling Group (force-delete termine les instances)
# aws autoscaling delete-auto-scaling-group \
#   --auto-scaling-group-name "nodejs-app-asg" \
#   --force-delete \
#   --region "$AWS_REGION"

# 3. Supprimer le Launch Template
# aws ec2 delete-launch-template \
#   --launch-template-id "$LAUNCH_TEMPLATE_ID" \
#   --region "$AWS_REGION"

# 4. Supprimer le Listener
# aws elbv2 delete-listener \
#   --listener-arn "<LISTENER-ARN>" \
#   --region "$AWS_REGION"

# 5. Supprimer l'ALB
# aws elbv2 delete-load-balancer \
#   --load-balancer-arn "$ALB_ARN" \
#   --region "$AWS_REGION"

# 6. Supprimer le Target Group (attendre que l'ALB soit supprimé)
# aws elbv2 delete-target-group \
#   --target-group-arn "$TARGET_GROUP_ARN" \
#   --region "$AWS_REGION"

# 7. Supprimer le Security Group ALB (si créé)
# aws ec2 delete-security-group \
#   --group-id "$ALB_SG_ID" \
#   --region "$AWS_REGION"

# ---------------------------------------------------------------------------
# RECAPITULATIF DE L'ARCHITECTURE DEPLOYEE
# ---------------------------------------------------------------------------
# Internet
#     |
#     v
# [ALB - nodejs-app-alb]          <- Subnets publics (2 AZ)
#     |  Port 80 (HTTP)
#     v
# [Target Group - nodejs-app-tg]  <- Health check sur /
#     |
#     +--------+--------+
#     |                 |
#     v                 v
# [EC2 - AZ-a]      [EC2 - AZ-b]  <- Auto Scaling Group (2 à 6 instances)
#     |                 |            <- Launch Template: nodejs-app-lt
#     +--------+--------+            <- Scaling: CPU cible 50%
#              |
#              v
#         [RDS MySQL]               <- Subnet privé, accessible via db-sg
#
# Flux de scaling :
#   CPU moyen > 50% -> AWS ajoute des instances (jusqu'à max=6)
#   CPU moyen < 50% -> AWS retire des instances (jusqu'à min=2)
# =============================================================================
