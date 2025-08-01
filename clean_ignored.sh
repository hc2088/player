#!/bin/bash
echo "正在移除 .gitignore 中列出的已跟踪文件..."
git ls-files --cached -i --exclude-from=.gitignore | xargs -r git rm --cached -r
echo "完成！请记得执行 git commit -m 'clean ignored files'"
