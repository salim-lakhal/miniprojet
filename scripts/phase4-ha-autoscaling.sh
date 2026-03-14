#!/bin/bash
# =============================================================================
# PHASE 4 — HIGH AVAILABILITY & AUTO SCALING
# =============================================================================
# Reference script for setting up ALB + Auto Scaling Group on AWS.
# NOT meant to be run as-is — replace all <PLACEHOLDER> values with your
# actual resource IDs before executing each section.
#
# Target architecture:
#   Internet -> ALB (public subnets, 2 AZs) -> ASG (2-6 EC2) -> RDS MySQL
#
# Prerequisites:
#   - Phase 1: VPC, subnets, Security Groups
#   - Phase 2: EC2 with working Node.js app
#   - Phase 3: RDS MySQL, Secrets Manager
#   - AWS CLI configured with proper permissions
#   - AMI created from Phase 2 EC2 instance
# =============================================================================

# ---------------------------------------------------------------------------
# CONFIGURATION — replace with your values
# ---------------------------------------------------------------------------

VPC_ID="<YOUR-VPC-ID>"
SUBNET_PUBLIC_1="<YOUR-SUBNET-PUBLIC-1>"
SUBNET_PUBLIC_2="<YOUR-SUBNET-PUBLIC-2>"
SUBNET_PRIVATE_1="<YOUR-SUBNET-PRIVATE-1>"
SUBNET_PRIVATE_2="<YOUR-SUBNET-PRIVATE-2>"

WEB_SG_ID="<YOUR-WEB-SG-ID>"
ALB_SG_ID="<YOUR-ALB-SG-ID>"

APP_AMI_ID="<YOUR-APP-AMI-ID>"
INSTANCE_TYPE="t2.micro"
KEY_PAIR_NAME="<YOUR-KEY-PAIR-NAME>"
SECRET_ARN="<YOUR-SECRET-ARN>"
AWS_REGION="us-east-1"
PROJECT_TAG="student-crud"
OWNER_TAG="<YOUR-NAME>"

# ---------------------------------------------------------------------------
# TASK 1: APPLICATION LOAD BALANCER
# ---------------------------------------------------------------------------

echo "=== TASK 1: Application Load Balancer ==="

# 1.1 Create a dedicated Security Group for the ALB
aws ec2 create-security-group \
  --group-name "alb-sg" \
  --description "Security Group for the Application Load Balancer" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=alb-sg},{Key=Project,Value=$PROJECT_TAG}]" \
  --region "$AWS_REGION"

# Allow inbound HTTP (port 80) from the internet
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION"

# Restrict EC2 web SG to only accept traffic from the ALB SG
aws ec2 authorize-security-group-ingress \
  --group-id "$WEB_SG_ID" \
  --protocol tcp \
  --port 80 \
  --source-group "$ALB_SG_ID" \
  --region "$AWS_REGION"

# 1.2 Create Target Group
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

TARGET_GROUP_ARN="<TARGET-GROUP-ARN>"

# 1.3 Create ALB across two public subnets for multi-AZ availability
aws elbv2 create-load-balancer \
  --name "nodejs-app-alb" \
  --subnets "$SUBNET_PUBLIC_1" "$SUBNET_PUBLIC_2" \
  --security-groups "$ALB_SG_ID" \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --tags "Key=Name,Value=nodejs-app-alb" "Key=Project,Value=$PROJECT_TAG" \
  --region "$AWS_REGION"

ALB_ARN="<ALB-ARN>"
ALB_DNS="<ALB-DNS-NAME>"

# 1.4 Create HTTP listener forwarding to the target group
aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$TARGET_GROUP_ARN" \
  --tags "Key=Name,Value=nodejs-app-listener-http" "Key=Project,Value=$PROJECT_TAG" \
  --region "$AWS_REGION"

# Verify ALB state
aws elbv2 describe-load-balancers \
  --names "nodejs-app-alb" \
  --query "LoadBalancers[0].{State:State.Code,DNSName:DNSName}" \
  --output table \
  --region "$AWS_REGION"

# ---------------------------------------------------------------------------
# TASK 2: EC2 AUTO SCALING
# ---------------------------------------------------------------------------

echo "=== TASK 2: Auto Scaling Group ==="

# 2.1 Create Launch Template
cat > /tmp/user-data.sh << 'USERDATA'
#!/bin/bash
if command -v pm2 &> /dev/null; then
  pm2 resurrect || pm2 start /home/ec2-user/app/index.js --name "nodejs-app"
  pm2 save
else
  cd /home/ec2-user/app && node index.js &
fi
USERDATA

USER_DATA_B64=$(base64 -w 0 /tmp/user-data.sh)

aws ec2 create-launch-template \
  --launch-template-name "nodejs-app-lt" \
  --version-description "Initial version - Phase 4" \
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

LAUNCH_TEMPLATE_ID="<LAUNCH-TEMPLATE-ID>"

# 2.2 Create Auto Scaling Group (min 2 instances across 2 AZs)
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

# 2.3 Target Tracking scaling policy — keep average CPU at 50%
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

# 2.4 (Optional) Step scaling for aggressive scale-out on CPU spikes
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

SCALE_OUT_POLICY_ARN="<SCALE-OUT-POLICY-ARN>"

aws cloudwatch put-metric-alarm \
  --alarm-name "nodejs-app-high-cpu" \
  --alarm-description "CPU > 70% - Scale Out" \
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

# Scale-in: remove 1 instance when CPU < 25% for 5 minutes
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "nodejs-app-asg" \
  --policy-name "nodejs-app-scale-in-step" \
  --policy-type "StepScaling" \
  --adjustment-type "ChangeInCapacity" \
  --step-adjustments "MetricIntervalUpperBound=0,ScalingAdjustment=-1" \
  --metric-aggregation-type "Average" \
  --region "$AWS_REGION"

SCALE_IN_POLICY_ARN="<SCALE-IN-POLICY-ARN>"

aws cloudwatch put-metric-alarm \
  --alarm-name "nodejs-app-low-cpu" \
  --alarm-description "CPU < 25% - Scale In" \
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

# Verify ASG state
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

# ---------------------------------------------------------------------------
# TASK 3: ACCESS THE APP VIA ALB
# ---------------------------------------------------------------------------

echo "=== TASK 3: Application access ==="

aws elbv2 describe-load-balancers \
  --names "nodejs-app-alb" \
  --query "LoadBalancers[0].DNSName" \
  --output text \
  --region "$AWS_REGION"

echo "Application URL: http://$ALB_DNS"

# ---------------------------------------------------------------------------
# TASK 4: LOAD TESTING
# ---------------------------------------------------------------------------

echo "=== TASK 4: Load testing ==="

ALB_URL="http://$ALB_DNS/"

# Apache Bench: 1000 requests, 50 concurrent
# ab -n 1000 -c 50 "$ALB_URL"

# Heavy load test: 100k requests, 200 concurrent, 5 min timeout
# ab -n 100000 -c 200 -t 300 -k "$ALB_URL"

# Monitor CPU during test
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

# Check scaling activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "nodejs-app-asg" \
  --max-items 10 \
  --query "Activities[*].{Status:StatusCode,Start:StartTime,Description:Description}" \
  --output table \
  --region "$AWS_REGION"

# ---------------------------------------------------------------------------
# CLEANUP (optional — tears down all Phase 4 resources)
# ---------------------------------------------------------------------------

# Order matters — respect dependency chain:
# 1. CloudWatch alarms
# 2. Auto Scaling Group (force-delete terminates instances)
# 3. Launch Template
# 4. ALB Listener
# 5. ALB
# 6. Target Group
# 7. ALB Security Group

# Uncomment to execute:
# aws cloudwatch delete-alarms --alarm-names "nodejs-app-high-cpu" "nodejs-app-low-cpu" --region "$AWS_REGION"
# aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "nodejs-app-asg" --force-delete --region "$AWS_REGION"
# aws ec2 delete-launch-template --launch-template-id "$LAUNCH_TEMPLATE_ID" --region "$AWS_REGION"
# aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION"
# aws elbv2 delete-target-group --target-group-arn "$TARGET_GROUP_ARN" --region "$AWS_REGION"
# aws ec2 delete-security-group --group-id "$ALB_SG_ID" --region "$AWS_REGION"
