------------------------------- MODULE MAuth -------------------------------

EXTENDS MCore

CONSTANTS
    RolePerms, UserRoles

AuthAssumption ==
    /\ DOMAIN RolePerms = Roles
    /\ \A r \in Roles :
        /\ DOMAIN RolePerms[r] = Collections
        /\ \A c \in Collections :
            RolePerms[r][c] \subseteq PermissionT
    /\ DOMAIN UserRoles = Users
    /\ \A u \in Users :
        UserRoles[u] \subseteq Roles

InitAuth == TRUE

UserPermissions(user, c) ==
    UNION { RolePerms[r][c] : r \in UserRoles[user] }

IsAdmin(user, c) ==
    /\ user \in Users
    /\ c \in Collections
    /\ "Admin" \in UserPermissions(user, c)

CanRead(user, c) ==
    /\ user \in Users
    /\ c \in Collections
    /\ \/ "Read" \in UserPermissions(user, c)
       \/ IsAdmin(user, c)

CanWrite(user, c) ==
    /\ user \in Users
    /\ c \in Collections
    /\ \/ "Write" \in UserPermissions(user, c)
       \/ IsAdmin(user, c)

CanMigrate(user) ==
    /\ user \in Users
    /\ \E c \in Collections :
        \/ "Migrate" \in UserPermissions(user, c)
        \/ IsAdmin(user, c)

AuthTypeInvariant ==
    AuthAssumption

AuthSpec ==
    /\ CoreAssumption
    /\ AuthAssumption
    
=============================================================================
