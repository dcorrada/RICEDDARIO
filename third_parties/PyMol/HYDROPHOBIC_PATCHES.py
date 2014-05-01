# coding: utf-8
# color_h
# -------
#
# PyMOL command to color protein molecules according to the hydrophobicity (Black and Mould scale)
#
# Amino acid scale values:
#
# PHE  0.499
# ILE  0.442
# LEU  0.442
# TYR  0.379
# TRP  0.377
# VAL  0.324
# MET  0.237
# PRO  0.210
# CYS  0.179
# ALA  0.115
# GLY  0.000
# THR −0.051
# SER −0.142
# LYS −0.218
# GLN −0.250
# ASN −0.265
# HYS −0.336
# GLU −0.458
# ASP −0.473
# ARG −0.501
#
#
# Usage:
# run [path]/HYDROPHOBIC_PATCHES.py
# color_h (selection)
#
from pymol import cmd

def color_h(selection='all'):
    s = str(selection)
    print s
    cmd.set_color('color_ile',[255,29,29])
    cmd.set_color('color_phe',[255,0,0])
    cmd.set_color('color_val',[255,89,89])
    cmd.set_color('color_leu',[255,29,29])
    cmd.set_color('color_trp',[255,62,62])
    cmd.set_color('color_met',[255,134,134])
    cmd.set_color('color_ala',[255,196,196])
    cmd.set_color('color_gly',[255,255,255])
    cmd.set_color('color_cys',[255,164,164])
    cmd.set_color('color_tyr',[255,61,61])
    cmd.set_color('color_pro',[255,148,148])
    cmd.set_color('color_thr',[229,229,255])
    cmd.set_color('color_ser',[183,183,255])
    cmd.set_color('color_his',[84,84,255])
    cmd.set_color('color_glu',[22,22,255])
    cmd.set_color('color_asn',[120,120,255])
    cmd.set_color('color_gln',[128,128,255])
    cmd.set_color('color_asp',[14,14,255])
    cmd.set_color('color_lys',[144,144,255])
    cmd.set_color('color_arg',[0,0,255])
    cmd.color("color_ile","("+s+" and resn ile)")
    cmd.color("color_phe","("+s+" and resn phe)")
    cmd.color("color_val","("+s+" and resn val)")
    cmd.color("color_leu","("+s+" and resn leu)")
    cmd.color("color_trp","("+s+" and resn trp)")
    cmd.color("color_met","("+s+" and resn met)")
    cmd.color("color_ala","("+s+" and resn ala)")
    cmd.color("color_gly","("+s+" and resn gly)")
    cmd.color("color_cys","("+s+" and resn cys)")
    cmd.color("color_tyr","("+s+" and resn tyr)")
    cmd.color("color_pro","("+s+" and resn pro)")
    cmd.color("color_thr","("+s+" and resn thr)")
    cmd.color("color_ser","("+s+" and resn ser)")
    cmd.color("color_his","("+s+" and resn his)")
    cmd.color("color_glu","("+s+" and resn glu)")
    cmd.color("color_asn","("+s+" and resn asn)")
    cmd.color("color_gln","("+s+" and resn gln)")
    cmd.color("color_asp","("+s+" and resn asp)")
    cmd.color("color_lys","("+s+" and resn lys)")
    cmd.color("color_arg","("+s+" and resn arg)")
cmd.extend('color_h',color_h)
