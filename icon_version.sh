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
# commit     git-提交哈希值
# branch     git-分支名
# version    app-版本号
# build_num  app-构建版本号
PLISTPATH="${SRCROOT}/AppIconVersion/Info.plist"

#version=`/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${CONFIGURATION_BUILD_DIR}/${INFOPLIST_PATH}"`
version=`/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${PLISTPATH}"`
#build_num=`/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${CONFIGURATION_BUILD_DIR}/${INFOPLIST_PATH}"`
build_num=`/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${PLISTPATH}"`
echo "version:$version--build_num:$build_num"

# 检查当前所处Git分支
if [ -d .git ] || git rev-parse --git-dir > /dev/null 2>&1; then
commit=`git rev-parse --short HEAD`
branch=`git rev-parse --abbrev-ref HEAD`
else
commit=`hg identify -i`
branch=`hg identify -b`
fi;

echo "commit:$commit--branch:$branch"

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
icons_path="${PROJECT_DIR}/AppIconVersion/Assets.xcassets/AppIcon.appiconset"
icons_dest_path="${PROJECT_DIR}/AppIconVersion/Assets.xcassets/AppIcon-Internal.appiconset"
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

