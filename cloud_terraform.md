

to run the command in the cli for AWS we need to had a key 

# Access keys in AWS 
we search for that and then we got some credentials

once we got that we export the keys in the terminal to connect to the aws services

# In PowerShell:
```
$env:AWS_ACCESS_KEY_ID="sssssssssss"
$env:AWS_SECRET_ACCESS_KEY="aaaaaaa"
```

# start terraform
```
cd terraform
terraform init
```

Windows (PowerShell) from the project root:
start the enviroment

we had [dev, test] NAMEENVIROMENT
```
.\scripts\deploy.ps1 -Environment NAMEENVIROMENT
```

destroy the enviroment with bash program
```
.\scripts\destroy.ps1 -Environment NAMEENVIROMENT
```

ro view the full list of resources that we had deploy
```
terraform show
```

# undestand which workspace we are 
List workspaces:
```
terraform workspace list
```
Switch workspace:
```
terraform workspace select dev
```
Show current workspace:
```
terraform workspace show
```










