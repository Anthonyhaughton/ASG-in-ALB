# Load Balancing a ASG with Jenkins Integration

In this project, we deployed four (at min) EC2 instances across four different AZ's in an ASG behind an ALB. We used a VPC module we created earlier and did most of the work in the `compute` and `alarm.tf` files. I came back to this on the 30th to clean up the VPC module and make more vars to be more modular. I think I can probably do the same for the other tf files, but I feel pretty confident at this point with creating most items in a VPC and things like ASGs/Alarms/Instances, but I want to work on another project with an ALB or NLB.

When this code is deployed, you will get `alb_dns_name = "dev-lb-tf-example.us-east-1.elb.amazonaws.com"` as output. When you paste that into a browser, you'll be able to hit a page that is showing its IP. If you refresh the page, it should go to another webserver with a different IP. I kept the routing basic, but you can set routing on a bunch of different factors. Just like my previous project, the CPU Util is monitored so when the ASG takes on load, it is able to scale out and in.

One of the places I got stuck for a bit was figuring why the ALB wasn't showing what my webservers were displaying. It was like my ASG and ALB were working independently. After digging, I found that the target group I created had zero machines register, so I tried to add them manually to see if permissions were the issue, but it worked fine. To get them to mesh, I was missing an `aws_autoscaling_attachment` that took in the `ash.id` and the `target_group.id`. After this was defined, the instances would spin up and be added to the TG.

Note:

1/2/2023:
Now that my I've been working with Jenkins, I see how important state is in Terraform. For this project and 'Static Site'
I moved my state file to a 's3' backend so that I can see the current state of my build where ever I am working as opposed to
my local computer. This also means I can destroy things that Jenkins builds without having to run a 'Replay' and edit the lines 
in one of the successful builds.

Architecture for this build but instead of west it's east because west doesn't have 4 AZs up currently.

![img](./docs/img.png)

## Jenkins Build Info

This was one of the first projects I deployed with Jenkins and learned a lot!

### Config and Install Jenkins

Here's how I set up Jenkins and created a pipeline to push out this Terraform code:

Install and configure Jenkins node (Amazon Linux AMI):

```bash
#!/bin/bash

# Set the desired key file and passphrase
KEY_FILE="$HOME/.ssh/jenkins_key"
PASSPHRASE=""

# Jenkins/Java
sudo yum update -y
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum upgrade
sudo dnf install java-17-amazon-corretto -y
sudo yum install jenkins -y
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Git
sudo yum install git -y

# Terraform
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform

# *Only needed for worker node* Generate SSH key for Jenkins builder and output key to /root/key.txt
ssh-keygen -t ed25519 -f "$KEY_FILE" -N "$PASSPHRASE"
cat /$HOME/.ssh/jenkins_key > /$HOME/key.txt
```

Build worker node, it's the same script as the head node but just don't need to install Jenkins.

When both machines are up ssh into the worker node and generate an ed25519 key. We will use the private key to configure the worker on Jenkins so it can build for us.

Now, we can get the IP from the Jenkins node and go to the browser and type in the IP:8080 and it should take you to the 'Jenkins init setup'.

After finishing the setup, we can start creating some keys, a user, and configure the worker node.

Configure ec2-user:

On the left in the pane, find 'Manage Jenkins' > 'Credentials' > 'System' > 'Global credentials (unrestricted)' > 'Add Creds'
Scope > Global | ID > 'ec2-user' | Name > 'ec2-user' | Paste in the private key we generated on the worker machine before.

Configure the worker node:

On the left in the pane, find 'Manage Jenkins' > 'Nodes' > 'New Node'.
I named mine ec2_worker, just keep in mind this is the name you will use when you configure the agent line on your Jenkinsfile.
Set 'Remote root directory' to /home/ec2-user/workspaces
Set 'Usage' to 'Use this node as much as possible'. Also make sure to configure the 'Built in Node' to 'Only build Jobs w/ label matching.. '
This will make it so that only the worker node will build preventing your host from slowing down.
Launch Method > 'Launch agents via SSH' then enter the IP in Host and choose the user we just created from the drop-down.
I set the 'Host Key Verification Strategy' to 'Non-verifying' but idk what this does.
Now that the node is configured you should be able to go back to the dashboard and see the machine is online. (You may have to go back to nodes and 'relaunch agent')

Lastly, we need to create the access and secret key. These will be used in the Jenkins file to auth into AWS and actually build the infrastructure. See the snippet below of how I used the vars to auth.
```
environment {
     AWS_ACCESS_KEY_ID = credentials('accesskey')
     AWS_SECRET_ACCESS_KEY = credentials('secretkey')
     AWS_REGION = "us-east-1"
 }
```
Once again, find 'Manage Jenkins' > 'Credentials' > 'System' > 'Global credentials (unrestricted)' > 'Add Creds'
Kind > 'Secret text file' | Scope > 'Global' Paste Access key | ID > $name_in_Jenkinsfile
Do the same for the Secret key.

### Building a pipline

Now that our user, worker node, and access keys are configured, we can start building a pipeline (I used Multibranch) to 
connect to our repo and start running the code provided.

To start, on the Dashboard choose 'New Item', name your proj and pick 'multibranch pipeline'. Next, fill in all the obvious 
stuff like 'Display Name', and 'Description'. Under 'Branch Sources' choose 'Add Source' > 'Git'. All that's needed here is 
the url of your GitHub repo. Everything else can be left as default. After saving, the project will try to scan your repo.
You can check weather there are any issues or if it doesn't detect a 'Jenkinsfile' by looking at the 'Scan MultiBranch Pipeline Log'.
If all is good you should just see 'SUCCESS' at the bottom of the log. 

If Jenkins was able to check out your repo, it will start building automatically. You can click into 'master' and see the build 
history. It's show if it was a success or failure, and you can view the logs of any build # attempt by clicking the date
and viewing the console output. Here's snip of a log of a successful build:

````
Apply complete! Resources: 13 added, 0 changed, 0 destroyed.
Outputs:

bucket_arn = "arn:aws:s3:::devhaughton.com"
bucket_name = "devhaughton.com"
cloudfront_domain_name = "dsws6bea2776j.cloudfront.net"

[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // withCredentials
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS
````
The console log is a great place to troubleshoot.