#!/bin/bash


#Create date and time
CDATETIME=`date  +%Y%m%d%H%M%S`

#Instance ID which instance you wanna create Autoscaling service
INS_ID="i-5c29d990"

#Autoscaling config name
AC_CONFIG="AC_$CDATETIME"
#Autoscaling group  name
AC_GROUP_NAME="AC_GROUP_byRay"

#desired-capacity
DC="1"
#security group
SG="sg-9b3a8bfe"


#which key pari
KP="ELB"

#specify machine type
INSTANCE_TYPE="t2.micro"
#which AMI you wanna use in autoscaling
#AMI_ID="ami-6a0d0438"

GP_MAX="1"
GP_MIN="1"

HN=`hostname`





# Specify InstanceID find the volume ID
VOL_ID=`aws ec2 describe-instances --instance-ids $INS_ID \
	--query 'Reservations[].Instances[].[BlockDeviceMappings[].Ebs.VolumeId  ]' `

# Specify the volume ID find the latest snpshot 
SNP_ID=`aws ec2 describe-snapshots --filters '{"Name":"status","Values":["completed"],"Name":"volume-id","Values":["'$VOL_ID'"]}' \
	--query 'Snapshots[*].{ID:SnapshotId,Time:StartTime}'|awk '{sprintf("date -d \"%s\" +%%s",$2)|getline d;print $1,d}'| \
	sort -k 2 -r |head -1|awk '{print $1}'` 

# Use the latest snapshot ID to create an AMI

if [[ -z $SNP_ID ]]
then
	echo "Cannot find snapshot ID.."
	exit 1
fi
AMI_ID=`aws ec2 \
register-image \
--name "AutoCreateAMI_$CDATETIME" \
--description "This AMI created by script $0,host:$HN" \
--virtualization-type hvm \
--architecture x86_64 \
--root-device-name "/dev/xvda" \
--block-device-mappings "[{ \"DeviceName\": \"/dev/xvda\",\"Ebs\": { \"SnapshotId\": \"snap-ad324f99\",\"VolumeType\":\"gp2\"} } ]"`


# Create autoscaling configuration
aws autoscaling create-launch-configuration --launch-configuration-name $AC_CONFIG \
	--image-id $AMI_ID --instance-type  $INSTANCE_TYPE \
	--security-groups "$SG" \
	--key-name $KP \
	--associate-public-ip-address


# Find AutoScaling Group


EX_AG=`aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].[AutoScalingGroupName]'`
EX=1
for exag in $EX_AG
do
	if [[ "$exag" == "$AC_GROUP_NAME" ]]
	then
		EX=0
		break
	fi
done


if [[ $EX -eq 0 ]]
then
	#AutoScaling Group existing
	#Update AutoScaling Group configuration
	echo "Updated"
	aws autoscaling update-auto-scaling-group --auto-scaling-group-name $AC_GROUP_NAME \
		--launch-configuration-name $AC_CONFIG
	

else
	
	# Create autoscaling group
	
	aws autoscaling create-auto-scaling-group --auto-scaling-group-name $AC_GROUP_NAME \
		--launch-configuration-name $AC_CONFIG \
		--availability-zones "ap-southeast-1b"  \
		--max-size $GP_MAX --min-size	$GP_MIN --desired-capacity $DC \
		--vpc-zone-identifier "subnet-07ee4c62"
	#--load-balancer-names "my-lb" 
fi


# Delete the previous autoscaling configuration.

Old_AC=`aws autoscaling describe-launch-configurations \
	--query 'LaunchConfigurations[].[LaunchConfigurationName]'| \
		sort -t "_" -k 2 -r|sed '1d'`

for oac in $Old_AC
do
	echo "Delete:$oac"
	aws autoscaling delete-launch-configuration --launch-configuration-name $oac
done

