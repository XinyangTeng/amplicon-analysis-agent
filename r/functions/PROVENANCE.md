# R function provenance

These scripts are a team-authorized snapshot supplied by the project owner from the team's
analysis function collection on 2026-07-22.

Repository integration changes:

- copied the 55 executable R functions and one shared adapter as a versioned snapshot;
- made optional dependencies load only when installed;
- added normalized inputs, explicit parameters, batch-isolated workspaces, run logs, and
  output validation;
- added native fallbacks where legacy wrappers were incompatible with current dependencies;
- retained the original statistical intent without claiming authorship.

Before a public tagged release, replace the snapshot date with the originating commit
identifier and confirm the complete author, copyright, and license information.

## Independent network extensions

`script_network_compositional.R`, `script_network_compare.R`, and their shared implementation
were written independently for this repository in 2026. They follow the public methodological
stages documented by NetCoMi (Peschel et al., Briefings in Bioinformatics, 2021) but do not copy
NetCoMi source code and do not require the NetCoMi package. NetCoMi itself is GPL-3; this project
is GPL-3.0-or-later. The local implementation is a deliberately smaller workflow and must not be
presented as a full or numerically identical reimplementation of NetCoMi.

## External package-backed methods

The adapters for ANCOM-BC2, ALDEx2, MaAsLin2/3, LinDA, corncob,
metagenomeSeq, LEfSe, breakaway, Generalized UniFrac, SPIEC-EASI, sPLS-DA,
SIAMCAT, WGCNA and CoDA PCA call the installed packages through their public
R interfaces. Package code was not copied into this repository. Each run writes
the backend package and version into a method table; the packages retain their
own authorship, copyright, citation and license requirements.
