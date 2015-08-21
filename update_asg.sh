#!/bin/bash


#Create date and time
CDATETIME=`date  +%Y%m%d%H%M%S`

#Instance ID which instance you wanna create Autoscaling service
INS_ID="i-d71f001a"
#Use instance name to find the latest snapshot id
INS_NAME="mo_cod_revamp_Prod"


#######################		AUTOSCALING CONFIGURATION	#######################
#Autoscaling config name
AC_CONFIG="mo_sc_AC_$CDATETIME"

#which key pari
KP="poc-mce"
#security group
SG="sg-141ebb71 sg-7608a713 sg-8c00ace9 sg-eae8698f sg-ed04a688"
#User data file:
LABDATA="labuserdata.txt"
#IAM PROFILE
IAM_PF="mo_scsource_prod"
#specify machine type
INSTANCE_TYPE="m3.medium"

#######################		END AUTOSCALING CONFIGURATION	#######################

#######################		AUTOSCALING GROUP	#######################
#Autoscaling group  name
AC_GROUP_NAME="mo_cod_revamp_Prod"
#desired-capacity
DC="1"




#subnet
SUBN="subnet-90a556e7"
#AZ
AZ="ap-southeast-1a"


GP_MAX="2"
GP_MIN="1"
#######################		END AUTOSCALING GROUP	#######################

HN=`hostname`





# Specify InstanceID find the volume ID
#VOL_ID=`aws ec2 describe-instances --instance-ids $INS_ID \
#	--query 'Reservations[].Instances[].[BlockDeviceMappings[].Ebs.VolumeId  ]' `


VOL_ID=`aws ec2 describe-instances --filters "Name=tag:Name,Values='$INS_NAME'" --query 'Reservations[].Instances[].[BlockDeviceMappings[].Ebs.VolumeId  ]'|tr -s '\n' ' ' `
#
volid=`awk -v info="$VOL_ID" 'BEGIN{lens=split(info,tA," ");for(k=1;k<=lens;k++){printf("\"%s\" ",tA[k]);}}'|tr -s " " ","|sed -e 's/[,]*$//g'`

## Specify the volume ID find the latest snpshot 
SNP_ID=`aws ec2 describe-snapshots \
	--filters '{"Name":"status","Values":["completed"],"Name":"volume-id","Values":['$volid]'}' \
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
--name "mo_sc_AutoCreateAMI_$CDATETIME" \
--description "This AMI created by script $0,host:$HN" \
--virtualization-type hvm \
--architecture x86_64 \
--root-device-name "/dev/xvda" \
--block-device-mappings "[{ \"DeviceName\": \"/dev/xvda\",\"Ebs\": { \"SnapshotId\": \"$SNP_ID\",\"VolumeType\":\"gp2\",\"VolumeSize\":20} } ]"`


# Create autoscaling configuration
aws autoscaling create-launch-configuration --launch-configuration-name $AC_CONFIG \
	--image-id $AMI_ID --instance-type  $INSTANCE_TYPE \
	--security-groups $SG \
	--key-name $KP \
	--iam-instance-profile $IAM_PF \
	--user-data file://$LABDATA \
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
		--availability-zones $AZ \
		--max-size $GP_MAX --min-size	$GP_MIN --desired-capacity $DC \
		--vpc-zone-identifier $SUBN \ 
		--load-balancer-names $ELB 
fi


# Delete the previous autoscaling configuration.

#Old_AC=`aws autoscaling describe-launch-configurations \
#	--query 'LaunchConfigurations[].[LaunchConfigurationName]'| \
#		sort -t "_" -k 2 -r|sed '1d'`
#
#for oac in $Old_AC
#do
#	echo "Delete:$oac"
#	aws autoscaling delete-launch-configuration --launch-configuration-name $oac
#done

