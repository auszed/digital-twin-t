
# git repo 

here are the steps to create a new readme
- create a route
- add name
- add the email that its hidden
- add files
- commit
- add the files to the remote repo in this case in git
- and finally push to the repo

```
git init -b main
git config user.name "auzed"
git config --global user.email "12837638+auszed@users.noreply.github.com"
git add .
git commit -m "Initial commit: Digital Twin infrastructure and application"
git remote add origin https://github.com/auszed/digital-twin-t.git
git push -u origin main
```

add a new branch to work on it
confirm the branch
```
git checkout -b NAMEBRANCH
git branch
git push -u origin NAMEBRANCH
```
