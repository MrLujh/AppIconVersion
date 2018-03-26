# iOS App图标版本化

绝大部分App都会有测试版、AppStore正式版，通常情况下，我们不能很快速的确定使用者安装App的环境，版本号，某个分支，某次提交的代码，这样一来，对测试和开发都造成一定的困惑，定位问题不够高效。

我们可以通过将重要信息，添加到App图标上，来提高测试环境定位问题的效率，这里简称：iOS图标版本化。


iOS图标版本化

## 一、如何获取需要覆盖图标的信息

* App版本号
* 构建版本号
* 分支名
* 提交哈希值

> 在App的plist文件中，可以通过PlistBuddy工具，直接提取相关信息。(根据Xcode中plist对应的key)
> Git命令行工具提供了rev-parse命令，Git探测工具，获取Git信息。

1.获取App版本号：

> version=`/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${CONFIGURATION_BUILD_DIR}/${INFOPLIST_PATH}"`

2.获取构建版本号：

> build_num=`/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${CONFIGURATION_BUILD_DIR}/${INFOPLIST_PATH}"`

3.获取Git分支名：

> branch=`git rev-parse --abbrev-ref HEAD`

4.获取Git提交哈希值：

> commit=`git rev-parse --short HEAD`

## 二、如何将关键信息覆盖到App图标？

ImageMagic是我用来从命令行处理图像的工具，它提供了大量的功能。

**首先确保安装imageMagick和ghostScript*，可以使用brew来简化安装过程：**

1.安装imageMagick

> brew install imagemagick

2.安装ghostScript

> brew install ghostscript

3.我们可以使用convert函数，通过指定参数，imageMagick会把文本覆盖在图片上面，还可以设置底部对齐和默认高度。

> imageMagick (TM) 是一个免费的创建、编辑、合成图片的软件。
> 它可以读取、转换、写入多种格式的图片。
> 图片切割、颜色替换、各种效果的应用，图片的旋转、组合，文本，直线，多边形，椭圆，曲线，附加到图片伸展旋转。

## 三、如何快速集成

**1. 拷贝下面的代码，保存为 icon_version.sh 脚本文件。**

**注意:**

icons_path和icons_dest_path路径，修改为自己工程，实际的图标资源路径或名称。

```objc
#!/bin/sh
convertPath=`which convert`
echo ${convertPath}
if [[ ! -f ${convertPath} || -z ${convertPath} ]]; then
echo "warning: Skipping Icon versioning, you need to install ImageMagick and ghostscript (fonts) first, you can use brew to simplify process:
brew install imagemagick
brew install ghostscript"
exit -1;
fi

# 说明
# commit     git-提交哈希值
# branch     git-分支名
# version    app-版本号
# build_num  app-构建版本号

version=`/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${CONFIGURATION_BUILD_DIR}/${INFOPLIST_PATH}"`
build_num=`/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${CONFIGURATION_BUILD_DIR}/${INFOPLIST_PATH}"`

# 检查当前所处Git分支
if [ -d .git ] || git rev-parse --git-dir > /dev/null 2>&1; then
commit=`git rev-parse --short HEAD`
branch=`git rev-parse --abbrev-ref HEAD`
else
commit=`hg identify -i`
branch=`hg identify -b`
fi;

shopt -s extglob
build_num="${build_num##*( )}"
shopt -u extglob
caption="${version}($build_num)\n${branch}\n${commit}"
echo $caption

function abspath() { pushd . > /dev/null; if [ -d "$1" ]; then cd "$1"; dirs -l +0; else cd "`dirname \"$1\"`"; cur_dir=`dirs -l +0`; if [ "$cur_dir" == "/" ]; then echo "$cur_dir`basename \"$1\"`"; else echo "$cur_dir/`basename \"$1\"`"; fi; fi; popd > /dev/null; }

function processIcon() {
base_file=$1
temp_path=$2
dest_path=$3

if [[ ! -e $base_file ]]; then
echo "error: file does not exist: ${base_file}"
exit -1;
fi

if [[ -z $temp_path ]]; then
echo "error: temp_path does not exist: ${temp_path}"
exit -1;
fi

if [[ -z $dest_path ]]; then
echo "error: dest_path does not exist: ${dest_path}"
exit -1;
fi

file_name=$(basename "$base_file")
final_file_path="${dest_path}/${file_name}"

base_tmp_normalizedFileName="${file_name%.*}-normalized.${file_name##*.}"
base_tmp_normalizedFilePath="${temp_path}/${base_tmp_normalizedFileName}"

# Normalize
echo "Reverting optimized PNG to normal"
echo "xcrun -sdk iphoneos pngcrush -revert-iphone-optimizations -q '${base_file}' '${base_tmp_normalizedFilePath}'"
xcrun -sdk iphoneos pngcrush -revert-iphone-optimizations -q "${base_file}" "${base_tmp_normalizedFilePath}"

width=`identify -format %w "${base_tmp_normalizedFilePath}"`
height=`identify -format %h "${base_tmp_normalizedFilePath}"`

band_height=$((($height * 50) / 100))
band_position=$(($height - $band_height))
text_position=$(($band_position - 8))
point_size=$(((12 * $width) / 100))

echo "Image dimensions ($width x $height) - band height $band_height @ $band_position - point size $point_size"

#
# blur band and text
#
convert "${base_tmp_normalizedFilePath}" -blur 10x8 /tmp/blurred.png
convert /tmp/blurred.png -gamma 0 -fill white -draw "rectangle 0,$band_position,$width,$height" /tmp/mask.png
convert -size ${width}x${band_height} xc:none -fill 'rgba(0,0,0,0.2)' -draw "rectangle 0,0,$width,$band_height" /tmp/labels-base.png
convert -background none -size ${width}x${band_height} -pointsize $point_size -fill white -gravity center -gravity South caption:"$caption" /tmp/labels.png

convert "${base_tmp_normalizedFilePath}" /tmp/blurred.png /tmp/mask.png -composite /tmp/temp.png

rm /tmp/blurred.png
rm /tmp/mask.png

#
# compose final image
#
filename=New"${base_file}"
convert /tmp/temp.png /tmp/labels-base.png -geometry +0+$band_position -composite /tmp/labels.png -geometry +0+$text_position -geometry +${w}-${h} -composite -alpha remove "${final_file_path}"

# clean up
rm /tmp/temp.png
rm /tmp/labels-base.png
rm /tmp/labels.png
rm "${base_tmp_normalizedFilePath}"

echo "Overlayed ${final_file_path}"
}

# Process all app icons and create the corresponding internal icons
# icons_dir="${SRCROOT}/Images.xcassets/AppIcon.appiconset"
icons_path="${PROJECT_DIR}/DaRenShop/Images.xcassets/AppIcon.appiconset"
icons_dest_path="${PROJECT_DIR}/DaRenShop/Images.xcassets/AppIcon-Internal.appiconset"
icons_set=`basename "${icons_path}"`
tmp_path="${TEMP_DIR}/IconVersioning"

echo "icons_path: ${icons_path}"
echo "icons_dest_path: ${icons_dest_path}"

mkdir -p "${tmp_path}"

if [[ $icons_dest_path == "\\" ]]; then
echo "error: destination file path can't be the root directory"
exit -1;
fi

rm -rf "${icons_dest_path}"
cp -rf "${icons_path}" "${icons_dest_path}"

# Reference: https://askubuntu.com/a/343753
find "${icons_path}" -type f -name "*.png" -print0 |
while IFS= read -r -d '' file; do
echo "$file"
processIcon "${file}" "${tmp_path}" "${icons_dest_path}"
done
```
**2. 将 icon_version.sh 放到 Xcode 工程目录。**

**3. 配置Xcode中的 Build Phases 选项卡，选择 New Run Script Phase 添加 Run Script。**

**4. shell 内容填写"${SRCROOT}/DaRenShop/Other/Release/icon_version.sh"**

**注意:**

${SRCROOT}/自己工程实际的文件路径/icon_version.sh

**5. 配置Xcode中的 General 选项卡，选择 App Icons and Launch Images项，将App Icons Source 修改为 AppIcon-Internal。**

**注意:**

按照实际生成AppIcon资源文件名修改

**6. 运行 Xcode 工程，自动生成一套，名为AppIcon-Internal，含有覆盖信息的App图标资源文件。**

## 四、总结

关于Xcode9构建iOS11系统的App图标时，不显示的问题：

> 使用Xcode9构建iOS11系统的App图标，默认读取资源文件，而非App包的Icon图标，导致不显示，使用本文中，通过生成独立的AppIcon-Internal资源文件:

- 不区分Release和Debug构建，都会生成AppIcon-Internal资源图标文件。
- 不区分Xcode版本，需要手动设置正式版、测试版的App Icons Source。
 
**另一种，通过AppIcon资源文件在App包中生成图标：**

- 区分Release和Debug构建，不会生成AppIcon-Internal资源图标文件，只在Debug下自动替换App原图标。
- 需要使用Xcode8构建，不需要手动设置正式版、测试版的App Icons Source。
- Xcode9构建iOS11系统图标时，会不显示。
