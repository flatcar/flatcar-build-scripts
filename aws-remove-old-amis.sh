#!/bin/bash -e

#
# Remove (deregister) old Flatcar AMIs from AWS account, and/or delete EBS
# snapshots.
#
# Requires a valid flatcar-linux aws API key + secret (e.g. jenkins')
#

AWS_REMOVE_OLDER_THAN="1 year ago" # this is a date(1) --date string

function print_aws() {
    # for --dry-run
    echo " [ command: 'aws $*' ]"
}
# --

function aws_list_amis() {
    local profile="$1"

    # We're not using --profile here since Jenkins does not have
    # "describe-regions" access rights
    local regions=""
    regions=$(aws ec2 describe-regions --all-regions  \
                             | jq -r '.Regions[] | "\(.RegionName)"')

    echo -n "Fetching images list from regions: "
    for r in $regions; do
        echo -n "$r "
        aws ec2 describe-images --owners 075585003325 \
                                 --profile "$profile" \
                                --region "$r"  \
            | jq -r '.Images[] | "\(.CreationDate),\(.ImageId),\(.Description),\(.BlockDeviceMappings[0].Ebs.SnapshotId) "' \
            | sort -t: -r -k1 > "region_$r.csv"
    done
    echo " - Done."
}
# --

function extract_old_amis() {
    local older_than_ts="$1"
    local region=""

    for region in region_*.csv; do
        local r="${region/#region_/}"
        echo "region,${r/\.csv/}"
        awk -F "," "\$1 < \"$older_than_ts\"" "$region"
        echo
    done
}
# --

function aws_unpublish_amis() {
    local aws"$1"
    local profile="$2"
    local ami_list="$3"
    local region=""

    while read -r line; do
        echo "$line" | grep -qE '^region,' && {
                                region=${line/*,/}
                                echo ""
                                echo "Region $region"
                                continue; }
        local id=""
        id=$(echo "$line" | awk -F "," '{print $2}')
        [ -n "$id" ] && {
            echo -n "processing $id "
            $aws ec2 --region "$region" \
                 deregister-image --image-id "$id" \
                 --profile "$profile" || true
            echo ""
        }
    done <"$ami_list"
}
# --

function aws_delete_snapshots() {
    local aws"$1"
    local profile="$2"
    local ami_list="$3"
    local region=""

    while read -r line; do
        echo "$line" | grep -qE '^region,' && {
                                region=${line/*,/}
                                echo ""
                                echo "Region $region"
                                continue
                            }
        local id=""
        id=$(echo "$line" | awk -F "," '{print $4}')
        [ -n "$id" ] && {
            echo -n "processing $id "
            $aws ec2 --region "$region" \
                 delete-snapshot --snapshot-id "$id" \
                 --profile "$profile" || true
            echo ""
        }
    done <"$ami_list"
}
# --

function aws_ami_status() {
    local profile="$1"
    local ami_list="$2"
    local region=""

    while read -r line; do
        echo "$line" | grep -qE '^region,' && {
                                region=${line/*,/}
                                echo ""
                                echo "Region $region"
                                continue
                            }
        local ami_id=""
        ami_id=$(echo "$line" | awk -F "," '{print $2}')
        local rel=""
        rel=$(echo "$line" | awk -F "," '{print $3}')
        local snap_id=""
        snap_id=$(echo "$line" | awk -F "," '{print $4}')

        [ -n "$ami_id" ] && {
            echo -n "$rel: AMI:"
            local out=""
            out=$(aws ec2 --profile "$profile" --region "$region" \
                                describe-images --image-ids "$ami_id" \
                        | jq -r '.Images[] | "\(.ImageId)"')
            [ -z "$out" ] && out="unavailable"
            echo -n "$out, EBS snapshot:"

            out=$(aws ec2 --profile "$profile" --region "$region" \
                                describe-snapshots --snapshot-ids "$snap_id" \
                        2>/dev/null | jq -r '.Snapshots[] | "\(.SnapshotId)"')
            [ -z "$out" ] && out="unavailable"
            echo "$out"
        }
    done <"$ami_list"
}
# --


function print_help() {
echo
echo -n "Usage: $0 [--profile <aws-profile>] [--delete <ami-list>]"
echo " [--unpublish <ami-list>] [--status <ami-list>] [--dry-run]"
echo -n "Retrieve AMI lists and generate list of old AMIs," 
echo " un-publish or delete AWS AMIs"
echo "   --profile <aws-profile> use <aws-profile> instead of 'default'."
echo "   --delete <ami-list> delete EBS snapshots in <ami-list>."
echo "   --unpublish <ami-list> un-publish AMIs in <ami-list>."
echo "   --status <ami-list> report AMI availability and EBS snapshot status."
echo -n "   <ami-list> is a list generated by running $0 w/o delete/unpublish/"
echo "status options."
echo -n "         --dry-run (only meaningful for delete/unpublish)"
echo " prints aws cli commands without executing them."
echo

}
# --
function aws_remove_old_amis() {
    local profile="default"
    local delete_file=""
    local unpublish_file=""
    local status_file=""
    local aws="aws"

    while [ 0 -lt $# ]; do
        case $1 in
            --profile)  profile="$2"; echo "Using profile $profile";
                        shift; shift;;
            --delete)   delete_file="$2"; shift; shift;;
            --unpublish)unpublish_file="$2"; shift; shift;;
            --status)   status_file="$2"; shift; shift;;
            --dry-run)  aws=print_aws; shift;;
            --help)     print_help; return;; 
            *)          print_help; return;; 
         esac
    done

    [ -f "$status_file" ] && {
        echo "Status of AMIs listed in $status_file."
        aws_ami_status "$profile" "$status_file"
        return
    }

    [ -f "$unpublish_file" ] && {
        echo "Un-publishing AMIs listed in $unpublish_file."
        aws_unpublish_amis "$aws" "$profile" "$unpublish_file"
    }

    [ -f "$delete_file" ] && {
        echo "Deleting all EBS snapshots listed in $delete_file."
        aws_delete_snapshots "$aws" "$profile" "$delete_file"
    }

    [ -f "$unpublish_file" ] || [ -f "$delete_file" ] && return

    local older_than=""
    older_than=$(date --date "$AWS_REMOVE_OLDER_THAN" +%Y-%m-%dT00:00:00.000Z)
    local result_file="amis_older_than_$older_than.csv"

    aws_list_amis "$profile"
    extract_old_amis "$older_than" > "$result_file"
    echo "$result_file created"
}
# --


if [ "$(basename "$0")" = "aws-remove-old-amis.sh" ] ; then
	aws_remove_old_amis "$@"
fi
