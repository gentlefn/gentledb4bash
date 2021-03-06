#!/bin/bash

# Copyright (C) 2011  Felix Rabe (www.felixrabe.net)
#
# GentleDB is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# GentleDB is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with GentleDB.  If not, see <http://www.gnu.org/licenses/>.


_gentledb_available_dbclasses=( $(python -c "import string, gentledb; print ' '.join(filter(lambda s: s.startswith(tuple(string.uppercase)), dir(gentledb)))") )

read -d '' _gentledb_py_header <<"EOT" || true
import errno, shutil, sys
import gentledb
DBClass = getattr(gentledb, sys.argv[1])
db_options = sys.argv[2]
if db_options == "-":
    db_options = []
elif db_options == "None":
    db_options = [None]
else:
    db_options = [db_options]
db = gentledb.Easy(DBClass(*db_options))
try:
    $pycmd
except IOError as (exc_errno, strerror):
    if exc_errno == errno.EPIPE:
        pass
    else:
        print >>sys.stderr, "ERROR:", strerror
        sys.exit(1)
except Exception as e:
    print >>sys.stderr, "ERROR:", e
    sys.exit(1)
EOT

function _gentledb_py {  # expects one argument or $pycmd, and $db_varname
    if [[ ${1--} != - ]] ; then
        local pycmd=$1
    fi
    [[ $# -ge 1 ]] && shift

    local db_class=${!db_varname%% *}
    local db_options=${!db_varname#* }
    pycmd=${_gentledb_py_header/\$pycmd/$pycmd}
    $do_debug && args python -u -c "$pycmd" "$db_class" "$db_options" "$@" > /dev/stderr
    python -u -c "$pycmd" "$db_class" "$db_options" "$@"
}

function args {
    python -c "import sys; print sys.argv[1:]" "$@"
}

# Used to detect unintentional running of the 'gentledb' function in a subshell
# (because then variable assignments would not propagate to the parent shell):
_gentledb_root_subshell=$BASH_SUBSHELL
function _gentledb_test_subshell {
    if [[ $BASH_SUBSHELL -ne $_gentledb_root_subshell ]] ; then
        echo "gentledb: This command does not work in subshells." > /dev/stderr
        return 1
    fi
    return 0
}


function _gentledb_var_or_val {
    local _varname=$1
    # Bash turns 'v=000 ; echo ${!v-$v}' into the value of $0, but we want '000':
    if [[ $_varname == 0* ]] ; then
        echo "$_varname"
    else
        echo "${!_varname-$_varname}"
    fi
}


function _gentledb_set {
    local varname=$1
    local command=$2
    local _value
    _value=$(eval "$command") || return 1
    export $varname="$_value"
}


function gentledb {
    local do_debug=false
    if [[ $# -ge 1 && $1 = -d ]] ; then
        local do_debug=true
        shift
    fi

    local pycmd


    ## INITIALIZE DB

    # gentledb db = DBClass [<db options>]
    if [[ ( $# -eq 3 || $# -eq 4 ) && $2 = = ]] ; then
        local db_varname=$1
        local dbclass_candidate=$3
        local db_options=${4--}

        local dbclass
        local dbclass_found=false
        for dbclass in "${_gentledb_available_dbclasses[@]}" ; do
            if [[ $dbclass = $dbclass_candidate ]] ; then
                dbclass_found=true
                break
            fi
        done
        if $dbclass_found ; then
            _gentledb_test_subshell || return 1
            export $db_varname="$dbclass $db_options"
            return
        fi
    fi


    ## GET DIRECTORY

    pycmd="print db.directory"

    # gentledb db getdir
    if [[ $# -eq 2 && $2 = getdir ]] ; then
        local db_varname=$1

        _gentledb_py
        return
    fi

    # gentledb directory = db getdir
    if [[ $# -eq 4 && $2 = = && $4 = getdir ]] ; then
        _gentledb_test_subshell || return 1
        local dir_varname=$1
        local db_varname=$3

        _gentledb_set $dir_varname _gentledb_py
        return
    fi


    ## GET FILENAME OF CONTENT OR POINTER

    pycmd="if True:
        i = sys.argv[3]
        ic = db.findc(i)
        ip = db.findp(i)
        ii = ic + ip
        if len(ii) != 1: raise gentledb.utilities.InvalidIdentifierException(i)
        i = ii[0]
        if ic:
            print db._get_content_filename(i)
        else:
            print db._get_pointer_filename(i)
        "

    # gentledb db file pid_or_cid
    if [[ $# -eq 3 && $2 = file ]] ; then
        local db_varname=$1
        local pid_or_cid=$(_gentledb_var_or_val "$3")

        _gentledb_py - "$pid_or_cid"
        return
    fi


    ## GET RANDOM ID

    pycmd="from gentledb.utilities import random; import sys; print random(sys.argv[1])"

    # gentledb random [prefix]
    if [[ ( $# -eq 1 || $# -eq 2 ) && $1 = random ]] ; then
        local prefix=${2-}
        python -u -c "$pycmd" "$prefix"
        return
    fi

    # gentledb pointer_id = random [prefix]
    if [[ ( $# -eq 3 || $# -eq 4 ) && $2 = = && $3 = random ]] ; then
        _gentledb_test_subshell || return 1
        local pid_varname=$1
        local prefix=${4-}

        _gentledb_set $pid_varname 'python -u -c "$pycmd" "$prefix"'
        return
    fi


    ## ADD CONTENT

    pycmd="f = db(); shutil.copyfileobj(sys.stdin, f); print f()"

    # gentledb db + < content-file
    if [[ $# -eq 2 && $2 = + ]] ; then
        local db_varname=$1

        _gentledb_py
        return
    fi

    # gentledb content_id = db + < content-file
    if [[ $# -eq 4 && $2 = = && $4 = + ]] ; then
        _gentledb_test_subshell || return 1
        local cid_varname=$1
        local db_varname=$3

        _gentledb_set $cid_varname _gentledb_py
        return
    fi

    pycmd="print db + sys.argv[3]"

    # gentledb db + "content"
    if [[ $# -eq 3 && $2 = + ]] ; then
        local db_varname=$1
        local ct=$3

        _gentledb_py - "$ct"
        return
    fi

    # gentledb content_id = db + "content"
    if [[ $# -eq 5 && $2 = = && $4 = + ]] ; then
        _gentledb_test_subshell || return 1
        local cid_varname=$1
        local db_varname=$3
        local ct=$5

        _gentledb_set $cid_varname '_gentledb_py - "$ct"'
        return
    fi


    ## GET CONTENT

    pycmd="shutil.copyfileobj(db(sys.argv[3]), sys.stdout)"

    # gentledb db - content_id > some-content
    if [[ $# -eq 3 && $2 = - ]] ; then
        local db_varname=$1
        local content_id=$(_gentledb_var_or_val "$3")

        _gentledb_py - "$content_id"
        return
    fi

    # gentledb content = db - content_id
    if [[ $# -eq 5 && $2 = = && $4 = - ]] ; then
        _gentledb_test_subshell || return 1
        local ct_varname=$1
        local db_varname=$3
        local content_id=$(_gentledb_var_or_val "$5")

        _gentledb_set $ct_varname '_gentledb_py - "$content_id"; echo x' || return 1
        eval "$ct_varname=\"\${$ct_varname%x}\""
        return
    fi


    ## SET POINTER ID TO EMPTY CONTENT

    # gentledb db pid = empty
    if [[ $# -eq 4 && $3 = = && $4 = empty ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "$2")

        _gentledb_py "db[sys.argv[3]] = db + ''" "$pointer_id"
        return
    fi


    ## CREATE A NEW POINTER ID TO EMPTY CONTENT

    pycmd="newid = gentledb.utilities.random(sys.argv[3]); db[newid] = db + ''; print newid"

    # gentledb db new [prefix]
    if [[ ( $# -eq 2 || $# -eq 3 ) && $2 = new ]] ; then
        local db_varname=$1
        local prefix=${3-}

        _gentledb_py - "$prefix"
        return
    fi

    # gentledb db pid = new [prefix]
    if [[ ( $# -eq 4 || $# -eq 5 ) && $3 = = && $4 = new ]] ; then
        local db_varname=$1
        local pid_varname=$2
        local prefix=${5-}

        _gentledb_set $pid_varname '_gentledb_py - "$prefix"'
        return
    fi


    ## SET POINTER ID TO CONTENT ID

    # gentledb db pointer_id = content_id
    if [[ $# -eq 4 && $3 = = ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "$2")
        local content_id=$(_gentledb_var_or_val "$4")

        _gentledb_py "db[sys.argv[3]] = sys.argv[4]" "$pointer_id" "$content_id"
        return
    fi


    ## FINDC AND FINDP

    pycmd="print '\n'.join(db.findc(sys.argv[3]))"

    # gentledb db findc [partial_content_id]
    if [[ ( $# -eq 2 || $# -eq 3 ) && $2 = findc ]] ; then
        local db_varname=$1
        local content_id=$(_gentledb_var_or_val "${3-}")

        _gentledb_py - "$content_id"
        return
    fi

    # gentledb content_id_list = db findc [partial_content_id]
    if [[ ( $# -eq 4 || $# -eq 5 ) && $2 = = && $4 = findc ]] ; then
        local cid_varname=$1
        local db_varname=$3
        local content_id=$(_gentledb_var_or_val "${5-}")

        _gentledb_set $cid_varname '_gentledb_py - "$content_id"'
        return
    fi

    pycmd="print '\n'.join(db.findp(sys.argv[3]))"

    # gentledb db findp [partial_pointer_id]
    if [[ ( $# -eq 2 || $# -eq 3 ) && $2 = findp ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "${3-}")

        _gentledb_py - "$pointer_id"
        return
    fi

    # gentledb pointer_id_list = db findp [partial_pointer_id]
    if [[ ( $# -eq 4 || $# -eq 5 ) && $2 = = && $4 = findp ]] ; then
        local pid_varname=$1
        local db_varname=$3
        local pointer_id=$(_gentledb_var_or_val "${5-}")

        _gentledb_set $pid_varname '_gentledb_py - "$pointer_id"'
        return
    fi


    ## GET CONTENT ID FROM POINTER ID

    pycmd="print db[sys.argv[3]]"

    # gentledb content_id = db pointer_id
    if [[ $# -eq 4 && $2 = = ]] ; then
        _gentledb_test_subshell || return 1
        local cid_varname=$1
        local db_varname=$3
        local pointer_id=$(_gentledb_var_or_val "$4")

        _gentledb_set $cid_varname '_gentledb_py - "$pointer_id"'
        return
    fi

    # gentledb db pointer_id > content-id-file
    if [[ $# -eq 2 ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "$2")

        _gentledb_py - "$pointer_id"
        return
    fi


    ## EDIT

    # gentledb db edit pointer_id
    if [[ $# -eq 3 && $2 = edit ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "$3")

        local fn
        fn="$(mktemp -t gentle_tp_da92_tmpfile_XXXXXXXX)" || return 1
        ( set +e ; (
            set -e  # cheap trap: inner block exits on failure, but outer block will be safe

            pycmd="shutil.copyfileobj(db(db[sys.argv[3]]), sys.stdout)"
            _gentledb_py - "$pointer_id" >| "$fn"

            "${EDITOR-vi}" "$fn"

            pycmd="f = db(); shutil.copyfileobj(sys.stdin, f); db[sys.argv[3]] = f()"
            _gentledb_py - "$pointer_id" < "$fn"
        ) )
        status=$?
        rm -f "$fn"

        return $status
    fi


    ## CAT

    # gentledb db cat pointer_id
    if [[ $# -eq 3 && $2 = cat ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "$3")

        _gentledb_py "shutil.copyfileobj(db(db[sys.argv[3]]), sys.stdout)" "$pointer_id"
        return
    fi


    ## EDITJSON

    # Pretty-prints JSON before editing, and compacts after.

    local pycmd_pprint="if True:
        import json
        j = db - db[sys.argv[3]]
        try:
            j = json.loads(j)
        except:
            sys.stdout.write(j)
        else:
            json.pretty(json.dump, j, sys.stdout)
            sys.stdout.write('\n')"

    local pycmd_compact="if True:
        import json
        j = sys.stdin.read()
        f = db()
        try:
            j = json.loads(j)
        except:
            f.write(j)
        else:
            json.compact(json.dump, j, f)
        db[sys.argv[3]] = f()"

    # gentledb db editjson pointer_id
    if [[ $# -eq 3 && $2 = editjson ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "$3")

        local fn
        fn="$(mktemp -t gentle_tp_da92_tmpfile_XXXXXXXX)" || return 1
        ( set +e ; (
            set -e  # cheap trap: inner block exits on failure, but outer block will be safe

            _gentledb_py "$pycmd_pprint" "$pointer_id" >| "$fn"
            "${EDITOR-vi}" "$fn"
            _gentledb_py "$pycmd_compact" "$pointer_id" < "$fn"
        ) )
        status=$?
        rm -f "$fn"

        return $status
    fi


    ## CATJSON

    # Pretty-prints JSON.

    # gentledb db catjson pointer_id
    if [[ $# -eq 3 && $2 = catjson ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "$3")

        _gentledb_py "$pycmd_pprint" "$pointer_id"
        return
    fi


    ## PUTJSON

    # Stores JSON compacted.

    # gentledb db putjson pointer_id
    if [[ $# -eq 3 && $2 = putjson ]] ; then
        local db_varname=$1
        local pointer_id=$(_gentledb_var_or_val "$3")

        _gentledb_py "$pycmd_compact" "$pointer_id"
        return
    fi


    echo NOT IMPLEMENTED > /dev/stderr
    return 1
}
