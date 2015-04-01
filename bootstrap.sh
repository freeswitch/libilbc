#!/bin/bash
aclocal
libtoolize -i --copy
autoconf
autoheader
automake --add-missing
