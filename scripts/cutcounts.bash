#!/bin/bash
# This is a modified version of the cutcounts script used in stampipes
set -x -e -o pipefail

if [[ $# -lt 2 ]] ; then
  echo "Usage: $0 in.bam output.starch" >&2
  exit 2
fi

bam=$1
CUTCOUNTS=$2

awk_cut="$(dirname $0)/cutfragments.awk"


name=$(basename $bam .bam)
outputdir="$(dirname $bam)"

FRAGMENTS=$outputdir/$name.fragments.sorted.bed.starch

if [[ -z "$TMPDIR" ]] ;then
  TMPDIR=$(mktemp -d)
fi
CUTS_BED=$TMPDIR/$name.cuts.sorted.bed

# temp files
CUTSTMP="$TMPDIR/cuts.bed"
FRAGMENTSTMP="$TMPDIR/fragments.bed"

# Create cut counts and fragments if they don't exist
if [[  ! -s "$CUTS_BED" || ! -s "$FRAGMENTS" ]]; then

  time bam2bed --do-not-sort < "$bam" \
    | awk -v "cutfile=$CUTSTMP" -v "fragmentfile=$FRAGMENTSTMP" -f "$awk_cut"
  sort-bed --max-mem 8G "$FRAGMENTSTMP" | starch - > "$FRAGMENTS"
  sort-bed --max-mem 8G "$CUTSTMP"      > "$CUTS_BED"

  rm -f "$CUTSTMP"
  rm -f "$FRAGMENTSTMP"

fi

if [[ ! -s "$CUTCOUNTS" ]]; then

  time bedops --chop 1 "$CUTS_BED" \
    | bedmap --faster --echo --count --delim "\t" - "$CUTS_BED" \
    | awk '{print $1"\t"$2"\t"$3"\tid-"NR"\t"$4}' \
    | starch - \
    > "$CUTCOUNTS"

  rm -f "$CUTS_BED"
fi
