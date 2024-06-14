# If arguments match path --resize, then resize the image
if [[ "$2" == "--resize" ]]; then
  img=$1
  filename=$(basename $img)
  new_filepath="./Rounded$filename"
  width=$(identify -format "%w" $img)
  height=$(identify -format "%h" $img)
  radius=$(echo "$width * 0.15" | bc)
  radius=$(printf "%.0f" $radius)
  convert -size ${width}x${height} xc:none -fill white -draw "roundRectangle 0,0,$width,$height,$radius,$radius" mask.png
  convert $img mask.png -compose DstIn -composite $new_filepath
  rm mask.png
  exit 0
fi

img_any=AppIcon.png
img_dark=AppIconDark.png
img_tinted=AppIconTinted.png
img_rounded=AppIconRounded.png
base_name=$(basename $img_any .png)
mkdir -p "${base_name}.appiconset"
jsonFile="Contents.json"
cp $jsonFile "${base_name}.appiconset"

jq -c '.images.[]' $jsonFile | while read -r item; do
  filename=$(echo "$item" | jq -r '.filename')
  echo "Detecting $filename"

  if [[ "$filename" == null ]]; then
    continue
  fi

  if [[ $filename == *rounded* ]]; then
    rounded=true
    size=${filename%-rounded.png}
  elif [[ $filename == *tinted* ]]; then
    tinted=true
    size=${filename%-tinted.png}
  elif [[ $filename == *dark* ]]; then
    dark=true
    size=${filename%-dark.png}
  else
    rounded=false
    tinted=false
    dark=false
    size=${filename%-any.png}
  fi

  outFile="${base_name}.appiconset/$filename"

  if [[ "$rounded" == "true" ]]; then
    echo "Converting $img_rounded to $outFile"
    convert "$img_rounded" -resize ${size}x${size} $outFile
  elif [[ "$tinted" == "true" ]]; then
    echo "Converting $img_tinted to $outFile"
    convert "$img_tinted" -resize ${size}x${size} $outFile
  elif [[ "$dark" == "true" ]]; then
    echo "Converting $img_dark to $outFile"
    convert "$img_dark" -resize ${size}x${size} $outFile
  else
    echo "Converting $img_any to $outFile"
    convert "$img_any" -resize ${size}x${size} $outFile
  fi
done
