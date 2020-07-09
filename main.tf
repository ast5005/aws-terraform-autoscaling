##################
# vpc set-up
##################

resource "aws_vpc" "main"{
  cidr="10.0.0.0/16"
  azs=["us-west-2a","us-west-2b","us-west-2c"]
  public_subnets=["10.0.101.0/24","10.0.102.0/24","10.0.103.0/24"]

  # enable_nat_gateway=true


  tag={
     Owner="ast"
     Environment="testing"
     Name="asg-vpc-0"
  }
}

###############################
# subnet
###############################

resource "aws_subnet" "subnet_1" {
  vpc_id=aws_vpc.main.id
  cidr_block="10.0.101.0/24"
  availablity_zone="us-west-2a"
}

resource "aws_subnet" "subnet_1" {
  vpc_id=aws_vpc.main.id
  cidr_block="10.0.102.0/24"
  availablity_zone="us-west-2b"
}

resource "aws_subnet" "subnet_1" {
  vpc_id=aws_vpc.main.id
  cidr_block="10.0.103.0/24"
  availablity_zone="us-west-2c"
}

###############################
# security group
################################
resource "aws_security_group" "default"{
  name="sec_gr_1"
  vpc_id=module.vpc.vpc_id
  ingress{
    description="SSH"
    from_port=22
    to_port=22
    cidr_blocks=["0.0.0.0/0"]
  }
  ingress{
    description="HTTP"
    from_port=80
    to_port=80
    cidr_blocks=["0.0.0.0/0"]
  }
  ingress{
    description="ICMP"
    from_port=ICMP
    to_port=ICMP
    cidr_blocks=["0.0.0.0/0"]
  }
  egress{
    from_port=0
    to_port=0
    protocol="-1"
    cidr_block=["0.0.0.0/0"]
  }
  tags={
    Name="allow_all"
  }
}
##########################
# instance set up
#########################
data "aws_ami" "ami_vm"{
  most_recent=true
  filter{
    name="name"
    values=var.ami_vm_name_filter
  }
  owners=var.ami_vm_owners
}

resource "aws_instance" "this"{
  ami=data.aws_ami.ami_vm.id
  instance_type="t2.micro"
  key_name=aws_key_pair.ec2key.key_name
}

############################
# key pair
############################

resource "aws_key_pair" "ec2key"{
  key_name    ="publicKey"
  public_key  ="${file(var.keypath)}"
}

##########################
#sns set up
#########################

resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = "arn:aws:sns:us-west-2:071229720313:auto-scaling-1-sns"
  protocol  = "sqs"
  endpoint  = "arn:aws:sqs:us-west-2:071229720313:auto-scaling-1"
}

###########################
#placement group
########################

resource "aws_placement_group" "rep_g"{
  name="rep_g"
  stategy="cluster"
}

######################
#auroscaling group
#####################

resources "aws_autoscaling_group" "asg"{
  name                      = "asg-1"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  placement_group           = aws_placement_group.rep_g.id
  launch_configuration      = aws_launch_configuration.lc_1.name
  vpc_zone_identifier       = module.vpc.id
}

########################
# launch configuration #
########################

resource "aws_launch_configuration" "this" {
  name                        = "lc_1"
  instance_type               = aws_instance.this.type
  key_name                    = aws_key_pair.ec2.name
  security_groups             = aws_security_group.default
  # load_balancers              = [module.eld.this_elb_id]
  # associate_public_ip_address = true
  # user_data                   = {}
  # user_data_base64            = {}
  # enable_monitoring           = var.enable_monitoring
  # spot_price                  = var.spot_price
  # placement_tenancy           = var.spot_price == "" ? var.placement_tenancy : ""
  # ebs_optimized               = var.ebs_optimized
}

#################################
# Autoscaling LiefeCycle Hook
#################################

resource "aws_autoscaling_lifecycle_hook" "as_lf_hook_1"{
  name="as_lf_hook_1"
  autoscaling_group_name="asg"
}

#################################
# aws_autoscaling_policy
#################################

resource "aws_autoscaling_policy" "scaleup"{
  name="asg_scaleup_policy"
  scaling_adjustment=1
  cooldown=300
  autoscaling_group_name=aws_autoscaling_group.asg.name
  adjustment_type="ChangeInCapacity"
}

resource "aws_autoscaling_policy" "scaledown"{
  name="asg_scaledown_policy"
  scaling_adjustment=-1
  cooldown=60
  autoscaling_group_name="asg"
  adjustment_type="ChangeInCapacity"
}

##########################
# Cloudwatch Alarm
##########################

resource "aws_cloudwatch_metric_alarm" "cpu_high_alarm"{
  alarm_name="asg_1_highcpu_alarm"
  comparison_operator="GreaterThanTreshold"
  evaluation_periods="2"
  metric_name="CPUUtilization"
  namespace="AWS/EC2"
  period="300"
  threshold="90"
  statistic="Average"

  dimensions={
    AutoScalingGroupName=aws_autoscaling_group.asg.name

  }
  alarm_description="Scale-up if CPU > 90% for 10 minutes"
  alarm_actions=[aws_autoscaling_policy.scaleup]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low_alarm"{
  alarm_name="asg_1_lowcpu_alarm"
  comparison_operator="LessThanTreshold"
  evaluation_periods="2"
  metric_name="CPUUtilization"
  namespace="AWS/EC2"
  period="300"
  threshold="70"
  statistic="Average"

  dimensions={
    AutoScalingGroupName=aws_autoscaling_group.asg.name

  }
  alarm_description="Scale-down if CPU > 70% for 10 minutes"
  alarm_actions=[aws_autoscaling_policy.scaledown]
}

#############################
# Application Load Balancer
#############################

resource "aws_lb" "alb_1"{
  name="asg_alb_1"
  internal=false
  load_balancer_type="application"
  subnets=module.vpc.public_subnets
  security_groups=[aws_security_group.default]
  tags={
    Environment="testing"
  }
}


resource "aws_lb_listener" "front_end"{
  load_balancer_arn=aws_lb.alb_1.arn
  port=80
  protocol="HTTP"

  default_action{
    type="forward"
    target_group_arn=
  }
}

resource  "aws_lb_target_group" "lb_tg_1"{
  name="lb_tg_1"
  port=80
  protocol="HTTP"
  vpc_id=module.vpc.id
}


#####################################
# OUTPUTS ###########################
#####################################

output "dnsname" {
  variable=aws_lb.alb_1.dns_name
}
