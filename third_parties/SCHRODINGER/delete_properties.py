__doc__="""
$Revision: 3.3 $

A script to delete all or named properties from a file and write the
results out to a new file. If a list of property names is given then only
those properties will be deleted from the file. If no list is given then
all properties will be deleted. A file containing the properties to be deleted
one per line can be specified with prop_file. This is optional.

Copyright Schrodinger, LLC. All rights reserved.
"""
# Contributors: D. Q. McDonald

import sys
from schrodinger.infra import mm
from schrodinger import structure
import os
import getopt
import sys
import argparse

_version = "$Revision: 3.3 $"

def delprop( infile, outfile, prop_list=[] ):
    """ Read all structures in infile, delete all properties from then
    and write them to outfile
    """

    prop = ""

    if os.path.isfile(outfile):
        os.unlink(outfile)
    for i, st in enumerate(structure.StructureReader(infile)):
        if len(prop_list) == 0:
            try:
                ur_handle = mm.mmct_ct_m2io_get_unrequested_handle(int(st))
                mm.m2io_delete_unrequested_handle(ur_handle)
                mm.mmct_ct_m2io_set_unrequested_handle(int(st),-1)
            except mm.MmException:
                print "Error deleting all properties"
        else:          
            ur_handle = mm.mmct_ct_m2io_get_unrequested_handle(int(st))
            for prop in prop_list:
                if i == 0:
                    if prop not in st.property.keys():
                        print "%s not found in input file. This property will not be deleted." % prop
                try:
                    mm.m2io_delete_named_data( ur_handle, prop )
                except mm.MmException:
                    #Ignore properties which don't exist for a given structure
                    pass
        st.append(outfile)

description = """
A script to delete all or named properties from a file and write the
results out to a new file. If a list of property names is given then only
those properties will be deleted from the file. If no list is given then
all properties will be deleted. A file containing the properties to be deleted
one per line can be specified with -prop_file. This is optional."""

epilog = """Examples

delete_properties.py input.mae output.mae
delete_properties.py input.maegz output.maegz -property_names r_i_glide_gscore
delete_properties.py input.mae.gz output.mae -property_names r_i_glide_gscore r_i_glide_evdw
delete_properties.py input.mae output.maegz -prop_file propfile.txt
"""

if __name__ == '__main__':
    script_desc = "$SCHRODINGER/run delete_properties.py <infile.mae> <outfile.mae> [options]"
                   
    parser = argparse.ArgumentParser(description=script_desc, version=_version, epilog=epilog, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("infile", help="Input file in Maestro format.")
    parser.add_argument("outfile", help="Output file in Maestro format.")
    parser.add_argument('-prop_file', action='store', dest='property_file', \
                        metavar='property_file', \
                        help='A text file containing the name of properties to \
                        delete.  Names must be given one per line.')
    parser.add_argument('-property_names', nargs='+', help='Optional list of \
                         property names to delete. Property names must be \
                         Maestro property names of the format x_y_z \
                         (e.g. s_m_title, not Title). Names must be separated \
                         by spaces or commas. If no names are given, all \
                         properties are deleted.')

    try:
        args = parser.parse_args()
    except IOError, msg:
        parser.error(str(msg))
        sys.exit(1)

    # Compile the list of property names to delete
    prop_list = []

    if args.property_names is not None:
        for prop in args.property_names:
            prop_list.extend(prop.split(','))

    if args.property_file is not None:
        try:
            afile=open(args.property_file, 'r')
        except:
            print "Cannot open property file: " + args.property_file
            sys.exit()
        for line in afile:
            line = line.strip()
            if line:
                prop_list.append(line)
        afile.close()

    if args.infile == args.outfile:
        msg  = 'The output file cannot be the same name as the input file.\n'
        msg += 'Please change the output file name and try again.'
        print msg
        sys.exit()

    delprop(args.infile, args.outfile, prop_list)

