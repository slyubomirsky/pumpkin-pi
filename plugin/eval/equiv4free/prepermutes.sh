#!/bin/bash

# Once you have uncommented the extremely costly normalization in main.v, this script normalizes it.

if [ -e ../out ]
then
  rm -r ../out
else
  :
fi

if [ -e main2.v ]
then
  rm main2.v
else
  :
fi

mkdir ../out
mkdir ../out/inputs
mkdir ../out/inorder
mkdir ../out/postorder
mkdir ../out/preorder
mkdir ../out/search
mkdir ../out/equivalences
mkdir ../out/normalized
cp main.v main2.v

# Remake CARROT case study code exactly once, to print terms
cd ..
make clean
make

# Copy the produced equivalences into the EFF code
for f in $(find out/equivalences/*.out); do
  name=$(basename "${f%.*}")
  line=$(grep -n "     : forall" $f | cut -d : -f 1)
  head -n $(($line-1)) $f > out/equivalences/$name-notyp.out
  dirname=$(echo $name | cut -d '-' -f 1)
  suffix=$(echo $name | cut -d '-' -f 2)
  defname=$dirname
  sed -i "s/$defname =/Definition $defname :=/" out/equivalences/$name-notyp.out
  echo "." >> out/equivalences/$name-notyp.out
  term=$(cat out/equivalences/$name-notyp.out)

  # https://stackoverflow.com/questions/29613304/is-it-possible-to-escape-regex-metacharacters-reliably-with-sed
  IFS= read -d '' -r < <(sed -e ':a' -e '$!{N;ba' -e '}' -e 's/[&/\]/\\&/g; s/\n/\\&/g' <<<"$term")
  term=${REPLY%$'\n'}
  
  sed -i "s/(\* EQUIV $name \*)/$term/" equiv4free/main2.v
done

# Copy the produced inputs into the EFF code
for f in $(find out/inputs/*.out); do
  name=$(basename "${f%.*}")
  line=$(grep -n "     :" $f | cut -d : -f 1)
  head -n $(($line-1)) $f > out/inputs/$name-notyp.out
  dirname=$(echo $name | cut -d '-' -f 1)
  suffix=$(echo $name | cut -d '-' -f 2)
  defname=$dirname
  sed -i "s/$defname =/Definition $defname :=/" out/inputs/$name-notyp.out
  echo "." >> out/inputs/$name-notyp.out
  term=$(cat out/inputs/$name-notyp.out)

  # https://stackoverflow.com/questions/29613304/is-it-possible-to-escape-regex-metacharacters-reliably-with-sed
  IFS= read -d '' -r < <(sed -e ':a' -e '$!{N;ba' -e '}' -e 's/[&/\]/\\&/g; s/\n/\\&/g' <<<"$term")
  term=${REPLY%$'\n'}
  
  sed -i "s/(\* INPUT $name \*)/$term/" equiv4free/main2.v
done

# Remake Univalent Parametricity case study code
cd equiv4free
make clean

echo "grab a coffee or a book; this will take a bit once you've uncommented the right line"
timeout 1h `time make equiv`

# Measure normalized term size
for f in $(find ../out/normalized/pre_permutes-sizedEFFequiv.out); do
  name=$(basename "${f%.*}")
  line=$(grep -n "     : forall" $f | cut -d : -f 1)
  head -n $(($line-1)) $f > ../out/normalized/$name-notyp.out
  coqwc -s ../out/normalized/$name-notyp.out
done


