import { LightningElement, track } from 'lwc';
 

export default class UserTestUI extends LightningElement {

     
    @track selectedUser = '';
    @track navigationItems = [
        { id: 'home', label: 'Home', icon: 'utility:home' },
        { id: 'contacts', label: 'Contacts', icon: 'utility:user' },
        { id: 'leads', label: 'Leads', icon: 'utility:cursor' },
        { id: 'accounts', label: 'Accounts', icon: 'utility:company' },
        { id: 'reports', label: 'Reports', icon: 'utility:file' },
        { id: 'users', label: 'Users', icon: 'utility:groups' },
        { id: 'userMagic', label: 'User Magic', icon: 'utility:magicwand' }
    ];

    @track permissionTypes = ['view', 'create', 'edit', 'delete', 'modifyAll'];

    @track permissionRows = [
        { id: '1', permission: 'Organization', view: false, create: false, edit: false, delete: false, modifyAll: false },
        { id: '2', permission: 'Object', view: false, create: false, edit: false, delete: false, modifyAll: false },
        { id: '3', permission: 'Field', view: false, create: false, edit: false, delete: false, modifyAll: false },
        { id: '4', permission: 'System', view: false, create: false, edit: false, delete: false, modifyAll: false }
    ];

    get userOptions() {
        return [
            { label: 'User One', value: 'user1' },
            { label: 'User Two', value: 'user2' },
            { label: 'User Three', value: 'user3' }
        ];
    }

    handleUserChange(event) {
        this.selectedUser = event.detail.value;
    }

    handlePermissionChange(event) {
        // Handle permission changes
        const permission = event.target.dataset.permission;
        const type = event.target.dataset.type;
        const checked = event.target.checked;
        
        this.permissionRows = this.permissionRows.map(row => {
            if (row.permission === permission) {
                return { ...row, [type]: checked };
            }
            return row;
        });
    }

    handleNewUser() {
        // Handle new user creation
    }

    handleCreate() {
        // Handle create action
    }

    handleNavClick(event) {
        // Handle navigation click
    } 
}
