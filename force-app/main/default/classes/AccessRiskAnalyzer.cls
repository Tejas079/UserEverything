public with sharing class AccessRiskAnalyzer {
    public class RiskResult {
        @AuraEnabled public Integer highRiskCount = 0;
        @AuraEnabled public Integer riskScore = 0;
        @AuraEnabled public String riskLevel = 'Low';
        @AuraEnabled public List<String> criticalFindings = new List<String>();
    }
    @AuraEnabled(cacheable=true)
    public static RiskResult analyzeUserRisk(Id userId) {
        RiskResult result = new RiskResult();
        UserPermController.UserPermissionAccess perms = UserPermController.getUserPermissionAccess(userId);
        
        // Define risk factors with explanations
        List<RiskCheck> riskChecks = new List<RiskCheck>{
            new RiskCheck(
                perms.systemPermissions.contains('ModifyAllData'),
                50,
                'Modify All Data permission grants full access to all records',
                true
            ),
            new RiskCheck(
                perms.systemPermissions.contains('ManageUsers'),
                30,
                'Manage Users permission allows user administration privileges',
                true
            ),
            new RiskCheck(
                perms.systemPermissions.contains('ApiEnabled'),
                20,
                'API Access enables programmatic access to data',
                false
            ),
            new RiskCheck(
                perms.objectPermissions.size() > 100,
                20,
                'Excessive object access (' + perms.objectPermissions.size() + ' objects)',
                true
            ),
            new RiskCheck(
                perms.systemPermissions.contains('ModifyAllData') && 
                perms.systemPermissions.contains('ApiEnabled'),
                0, // Score already accounted for in individual checks
                'Critical combination: Modify All Data + API Access',
                true
            )
        };

        // Process risk checks
        for(RiskCheck check : riskChecks) {
            if(check.condition) {
                result.riskScore += check.score;
                if(check.isCritical) {
                    result.criticalFindings.add(check.message);
                    result.highRiskCount++;
                }
            }
        }

        // Cap maximum score at 100
        result.riskScore = Math.min(result.riskScore, 100);
        
        result.riskLevel = determineRiskLevel(result.riskScore);
        return result;
    }

    // Helper class for risk factors
    private class RiskCheck {
        Boolean condition;
        Integer score;
        String message;
        Boolean isCritical;
        
        RiskCheck(Boolean condition, Integer score, String message, Boolean isCritical) {
            this.condition = condition;
            this.score = score;
            this.message = message;
            this.isCritical = isCritical;
        }
    }
    
    private static String determineRiskLevel(Integer score) {
        if(score >= 70) return 'Critical';
        if(score >= 50) return 'High';
        if(score >= 30) return 'Medium';
        return 'Low';
    }
}