# Lab Steps — Building a Highly Available, Scalable Web Application

## Phase 1: Planning the design and estimating cost
- [ ] Task 1: Create architectural diagram
- [ ] Task 2: Develop cost estimate (AWS Pricing Calculator, us-east-1, 12 months)

## Phase 2: Creating a basic functional web application
- [ ] Task 1: Create virtual network (VPC + subnets)
- [ ] Task 2: Create virtual machine (EC2 t2.micro, Ubuntu, SolutionCodePOC as User Data)
- [ ] Task 3: Test deployment (access via IPv4, test CRUD)

## Phase 3: Decoupling the application components
- [ ] Task 1: Change VPC config (private subnets in minimum 2 AZs)
- [ ] Task 2: Create RDS MySQL (only web app can access, no enhanced monitoring)
- [ ] Task 3: Configure Cloud9 environment (t3.micro, SSH connection)
- [ ] Task 4: Provision Secrets Manager (Script-1 from cloud9-scripts.yml)
- [ ] Task 5: Provision new EC2 for web server (Solution Code App Server, attach LabInstanceProfile/LabRole)
- [ ] Task 6: Migrate database (Script-3 from cloud9-scripts.yml)
- [ ] Task 7: Test application (CRUD via new EC2)

## Phase 4: Implementing high availability and scalability
- [ ] Task 1: Create Application Load Balancer (minimum 2 AZs)
- [ ] Task 2: Implement EC2 Auto Scaling (AMI from running instance, launch template, ASG with target tracking policy)
- [ ] Task 3: Access application (test CRUD via ALB DNS)
- [ ] Task 4: Load test (Script-2 from cloud9-scripts.yml, loadtest tool)

## Solution Requirements Checklist
- [ ] Functional: CRUD works without delay
- [ ] Load balanced: ALB distributes traffic
- [ ] Scalable: Auto Scaling Group adjusts capacity
- [ ] Highly available: Multiple AZs, ASG replaces failed instances
- [ ] Secure: DB in private subnet, correct ports only, no hardcoded credentials (Secrets Manager)
- [ ] Cost optimized: t2.micro, appropriate instance sizes
- [ ] High performing: No delay under normal/variable/peak loads

## Key Assumptions
- Single AWS Region (us-east-1)
- No HTTPS or custom domain needed
- Ubuntu AMI + JavaScript code provided
- Database in single AZ only
- Website publicly accessible without auth
- Cost estimation is approximate
