AC_INIT([erlang-http], [1.0.0], [ruslan@babayev.com])

AC_PREREQ([2.64])
AC_COPYRIGHT([Copyright (C) 2009 Ruslan Babayev])
AM_INIT_AUTOMAKE

AC_ERLANG_NEED_ERLC
AC_PREFIX_PROGRAM(erl)
AC_ERLANG_SUBST_ROOT_DIR
AC_ERLANG_SUBST_LIB_DIR
AC_ERLANG_SUBST_ERTS_VER
AC_ERLANG_CHECK_LIB([kernel])
AC_ERLANG_CHECK_LIB([stdlib])
AC_ERLANG_CHECK_LIB([crypto])
AC_ERLANG_CHECK_LIB([ssl])
AC_ERLANG_CHECK_LIB([amf])
AC_ERLANG_SUBST_INSTALL_LIB_SUBDIR([http], [1.0.0])

AC_CONFIG_FILES([Makefile src/http.app src/http.rel src/overview.edoc
	src/Makefile examples/Makefile])
AC_OUTPUT
