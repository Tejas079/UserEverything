public with sharing class UserPermissionAccess {
    @AuraEnabled public List<String> systemPermissions;
    @AuraEnabled public List<ObjectPermissions> objectPermissions;
    
    public UserPermissionAccess() {
        systemPermissions = new List<String>();
        objectPermissions = new List<ObjectPermissions>();
    }
}