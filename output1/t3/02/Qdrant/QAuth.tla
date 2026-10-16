------------------------------- MODULE QAuth -------------------------------

EXTENDS QCore

VARIABLE permission

AuthVars == <<permission>>

InitAuth ==
    LET p_admin == CHOOSE p \in Principals : TRUE
        p_no    == CHOOSE p \in Principals \ {p_admin} : TRUE
    IN
    permission = [p \in Principals |->
        [c \in Collections |->
            IF p = p_admin THEN {"Manage"} ELSE {} ]]

CanAccess(p, c, op) ==
    op \in permission[p][c] \/ "Manage" \in permission[p][c]

NextAuth == UNCHANGED AuthVars

AuthTypeOK ==
    permission \in [Principals -> [Collections -> SUBSET Operations]]

=============================================================================
