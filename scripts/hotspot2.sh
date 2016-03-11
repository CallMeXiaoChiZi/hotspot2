#! /bin/bash

usage(){
  cat >&2 <<__EOF__
Usage:  "$0" [options] in.bam out_spots.bed

Options:
    -h                    Show this helpful help

  Mandatory options:
    -c CHROM_SIZES_FILE   The length of each chromosome, in BED or starch format
                          Must include all chromosomes present in BAM input

  Recommended options:
    -e EXCLUDE_FILE       Exclude these regions from analysis

  Optional options:
    -n NEIGHBORHOOD_SIZE  Local neighborhood size (100)
    -w WINDOW_SIZE        Background region size  (25000)
    -p PVAL_FDR           Number of p-values to use for FDR (1000000)
    -f FDR_THRESHOLD      The false-discovery rate to use for filtering (0.05)
    -O                    Use non-overlapping windows (advanced option)

    -s SEED               Set this to an integer for repeatable results

    Both the exclude file and chromosome sizes file should be in bed or starch
    format.

    Neighborhood and window sizes are specified as the distance from the edge
    to the center - i.e, a 100bp neighborhood size is a 201bp window.

    Using non-overlapping windows is not recommended for most users.

__EOF__
    exit 2
}


EXCLUDE_THESE_REGIONS="/dev/null"
CHROM_SIZES=""
SITE_NEIGHBORHOOD_HALF_WINDOW_SIZE=100 # i.e., 201bp regions
BACKGROUND_WINDOW_SIZE=50001 # i.e., +/-25kb around each position
PVAL_DISTN_SIZE=1000000
OVERLAPPING_OR_NOT="overlapping"
FDR_THRESHOLD="0.05"
SEED=""

CUTCOUNT_EXE="$(dirname "$0")/cutcounts.bash"

while getopts 'hc:e:m:n:p:s:w:O' opt ; do
  case "$opt" in
    h)
      usage
      ;;
    c)
      CHROM_SIZES=$OPTARG
      ;;
    e)
      EXCLUDE_THESE_REGIONS=$OPTARG
      ;;
    n)
      SITE_NEIGHBORHOOD_HALF_WINDOW_SIZE=$OPTARG
      ;;
    O)
      OVERLAPPING_OR_NOT="nonoverlapping"
      ;;
    p)
      PVAL_DISTN_SIZE=$OPTARG
      ;;
    s)
      SEED=$OPTARG
      ;;
    w)
      BACKGROUND_WINDOW_SIZE=$(( 2 * OPTARG + 1 ))
      ;;

  esac
done
shift $((OPTIND-1))

COUNTING_EXE=tallyCountsInSmallWindows
HOTSPOT_EXE=hotspot2

if [[ -z "$1" || -z "$2" || -z "$CHROM_SIZES" ]]; then
  usage
fi

BAM=$1
HOTSPOT_OUTFILE=$2

outdir="$(dirname "$HOTSPOT_OUTFILE")"

CUTCOUNTS="$outdir/$(basename "$BAM" .bam).cutcounts.starch"
OUTFILE="$outdir/$(basename "$BAM" .bam).allcalls.starch"

TMPDIR=${TMPDIR:-$(mktemp -d)}

echo "Cutting..."
bash "$CUTCOUNT_EXE" "$BAM" "$CUTCOUNTS"

echo "Running hotspot2..."
unstarch "$CUTCOUNTS" \
    | "$COUNTING_EXE" "$SITE_NEIGHBORHOOD_HALF_WINDOW_SIZE" "$OVERLAPPING_OR_NOT" "reportEachUnit" "$CHROM_SIZES" \
    | bedops -n 1 - "$EXCLUDE_THESE_REGIONS" \
    | "$HOTSPOT_EXE" "$BACKGROUND_WINDOW_SIZE" "$PVAL_DISTN_SIZE" $SEED \
    | starch - \
    > "$OUTFILE"


# P-values of 0 will exist, and we don't want to do log(0).
# Roughly 1e-308 is the smallest nonzero P usually seen,
# so we can cap everything at that, or use a different tiny value.
# The constant c below converts from natural logarithm to log10.

echo "Thresholding..."
unstarch "$OUTFILE" \
  | awk -v "threshold=$FDR_THRESHOLD" '{if($6 <= threshold){print}}' \
  | bedops -m - \
  | bedmap --faster --delim "\t" --echo --min - "$OUTFILE" \
  | awk 'BEGIN{OFS="\t";c=-0.4342944819}
    {
      if($4>1e-308) {
        print $1, $2, $3, "id-"NR, c*log($4)
      } else {
        print $1, $2, $3, "id-"NR, "308"
      }
    }' \
   | starch - \
   > "$HOTSPOT_OUTFILE"

echo "Done!"

exit
