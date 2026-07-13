# msh-source: smoosh/tests/shell/semantics.case.ec.test
# msh-profile: posix
# msh-run: eval
(exit 3)
echo $?
case a in
    ( b ) (exit 4) ;;
    ( * ) ;;
esac
echo $?

(exit 5)
case a$(echo $?>ec) in
    ( b ) (exit 6) ;;
esac
echo $?
read ec_value <ec
[ "$ec_value" = "5" ] || exit 2

false
case a in
    ( a ) echo visible $? ;;
esac

false
case a in
    ( b ) (exit 6) ;;
esac
echo $?
