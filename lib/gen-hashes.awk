# Generate crypt-hashes.h from hashes.lst and configure settings.
#
#   Copyright 2018 Zack Weinberg
#
#   This library is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser General Public License
#   as published by the Free Software Foundation; either version 2.1 of
#   the License, or (at your option) any later version.
#
#   This library is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public
#   License along with this library; if not, see
#   <https://www.gnu.org/licenses/>.

BEGIN {
    next_output = 0
    error = 0
    default_prefix = ""

    # ENABLED_HASHES is set on the command line.
    split(ENABLED_HASHES, enabled_hashes_list, ",")
    for (i in enabled_hashes_list) {
        h = enabled_hashes_list[i]
        if (h != "") {
            hash_enabled[h] = 1
        }
    }
}

/^#/ {
    next
}

{
    if ($1 == ":") {
        printf("%s:%d: error: method name cannot be blank\n", FILENAME, NR) \
            > "/dev/stderr"
        error = 1
    }
    # No two hashing method names can be the same.
    if ($1 in line_index) {
        printf("%s:%d: error: method name '%s' reused\n", FILENAME, NR, $1);
        printf("%s: note: previous use was here\n", line_index[$1]);
        error = 1
    } else {
        line_index[$1] = sprintf("%s:%d", FILENAME, NR);
        if (!($1 in hash_enabled)) {
            hash_enabled[$1] = 0
        }
        default_cand[$1] = ""
        output_order[next_output++] = $1
    }
    if ($2 == ":") $2 = ""
    prefixes[$1] = $2
    if ($3 !~ /^[0-9]+$/ || $3 == 0) {
        printf("%s:%d: nrbytes must be a positive integer\n", FILENAME, NR) \
            > "/dev/stderr"
        error = 1
    }

    crypt_fn   = "crypt_" $1 "_rn"
    gensalt_fn = "gensalt_" $1 "_rn"

    renames[$1] = \
        "#define " crypt_fn " _crypt_" crypt_fn "\n" \
        "#define " gensalt_fn " _crypt_" gensalt_fn "\n"
    prototypes[$1] = \
        "extern void " crypt_fn " (const char *, size_t, const char *,\n" \
        "                size_t, uint8_t *, size_t, void *, size_t);\n" \
        "extern void " gensalt_fn " (unsigned long,\n" \
        "                const uint8_t *, size_t, uint8_t *, size_t);\n"

    table_entry[$1] = sprintf("  { \"%s\", %d, %s, %s, %d }, \\",
                              $2, length($2), crypt_fn, gensalt_fn, $3)

    if ($4 == ":") $4 = ""
    split($4, flags, ",")
    for (i in flags) {
        flag = flags[i]
        if (flag == "DEFAULT") {
            default_cand[$1] = $2
        } else if (flag == "STRONG"  || flag == "GLIBC"   || \
                   flag == "ALT"     || flag == "FEDORA"  || \
                   flag == "FREEBSD" || flag == "NETBSD"  || \
                   flag == "OPENBSD" || flag == "OSX"     || \
                   flag == "OWL"     || flag == "SOLARIS" || \
                   flag == "SUSE") {
            # handled in sel-hashes.awk
        } else {
            printf("%s:%d: unrecognized flag %s\n", FILENAME, NR, flag) \
                > "/dev/stderr"
            error = 1
        }
    }
}


END {
    # No hash prefix can be a prefix of any other hash prefix, except
    # for the empty prefix.
    for (i in prefixes) {
        a = prefixes[i]
        if (a == "") { continue }
        for (j in prefixes) {
            if (i == j) { continue }
            b = prefixes[j]
            if (b == "") { continue }
            if (substr(b, 1, length(a)) == a) {
                printf("%s: error: prefix collision: '%s' begins with '%s'\n",
                       line_index[j], b, a) > "/dev/stderr"
                printf("%s: note: '%s' is used here\n", line_index[i], a) \
                    > "/dev/stderr"
                error = 1
            }
        }
    }

    if (error) {
        exit 1
    }

    print "/* Generated by genhashes.awk from hashes.lst.  DO NOT EDIT.  */"
    print ""
    print "#ifndef _CRYPT_HASHES_H"
    print "#define _CRYPT_HASHES_H 1"

    print ""
    for (i = 0; i < next_output; ++i) {
        hash = output_order[i]
        printf("#define INCLUDE_%-13s %d\n", hash, hash_enabled[hash])
        if (hash_enabled[hash] && default_cand[hash] != "" && default_prefix == "") {
            default_prefix = default_cand[hash]
        }
    }

    print ""
    print "/* Internal symbol renames for static linkage, see crypt-port.h.  */"
    for (i = 0; i < next_output; ++i) {
        hash = output_order[i]
        if (hash_enabled[hash]) {
            print renames[hash]
        }
    }

    print "/* Prototypes for hash algorithm entry points.  */"
    for (i = 0; i < next_output; ++i) {
        hash = output_order[i]
        if (hash_enabled[hash]) {
            print prototypes[hash]
        }
    }

    print "#define HASH_ALGORITHM_TABLE_ENTRIES \\"
    for (i = 0; i < next_output; ++i) {
        hash = output_order[i]
        if (hash_enabled[hash]) {
            print table_entry[hash]
        }
    }
    print "  { 0, 0, 0, 0, 0 }"

    print ""
    if (default_prefix != "") {
        print "#define HASH_ALGORITHM_DEFAULT \"" default_prefix "\""
        print ""
    }
    print "#endif /* crypt-hashes.h */"
}
