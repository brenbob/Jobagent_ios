//
//  CompanyDetail.swift
//  jobagent
//
//  Created by Brenden West on 6/27/17.
//
//

import UIKit
import CoreData

@objc internal class CompanyDetail: UIViewController, UITableViewDelegate, UITableViewDataSource, TextFieldTableViewCellDelegate, EditItemDelegate, PickListDelegate {
    
    @IBOutlet weak var tableView: UITableView?
    @IBOutlet weak var btnCompanyActions: UISegmentedControl!

    weak var selectedCompany: Company?
    var managedObjectContext: NSManagedObjectContext!
    var currentKey: String = ""
    
    let fields : [ModelFieldType] = [.name, .location, .type, .notes]

    let companyTypes = [
        NSLocalizedString("STR_CO_TYPE_DEFAULT", comment: ""),
        NSLocalizedString("STR_CO_TYPE_AGENCY", comment: ""),
        NSLocalizedString("STR_CO_TYPE_GOVT", comment: ""),
        NSLocalizedString("STR_CO_TYPE_EDUC", comment: ""),
        NSLocalizedString("STR_OTHER", comment: "")
    ];

    required init?(coder aDecoder: NSCoder) {
        
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.automaticallyAdjustsScrollViewInsets = false;

        self.tableView?.register(UINib(nibName: "TextFieldTableViewCell", bundle: nil), forCellReuseIdentifier: "TextFieldTableViewCell")
        
        self.btnCompanyActions.addTarget(self, action: #selector(segmentAction(sender:)), for: .valueChanged)
        
        self.tableView?.reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // trigger text fields to save contents
        self.view.window?.endEditing(true)

        if let name = self.selectedCompany?.name, !name.isEmpty {
            do {
                try self.selectedCompany?.managedObjectContext?.save()
            } catch let error {
                print("Error on save: \(error)")
            }
        } else {
            // delete empty record from data source
            self.selectedCompany?.managedObjectContext?.delete(self.selectedCompany!)
        }
    }

    // MARK: TabelView methods
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return fields.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let field = fields[indexPath.row]
        let cell = self.tableView?.dequeueReusableCell(withIdentifier: "TextFieldTableViewCell", for: indexPath) as! TextFieldTableViewCell
        cell.configureWithField(field: field, andValue: self.selectedCompany?.stringValueFor(field: field))
        cell.delegate = self
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        // store name if entered
        self.view.endEditing(true)
        let field = fields[indexPath.row]
        
        // store ID of selected row for use when returning from child vc
        self.currentKey = field.rawValue
        
        switch self.currentKey {
        case "type":
            
            let pickList = PickList()
            pickList.header = NSLocalizedString("STR_SEL_TYPE", comment: "")
            pickList.options = companyTypes
            pickList.selectedItem = self.selectedCompany?.stringValueFor(field: field)
            pickList.delegate = self as PickListDelegate
            self.navigationController?.pushViewController(pickList, animated: true)
            break
            
        default:
            self.performSegue(withIdentifier: "showItem", sender: field)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showItem" {
            if let field = sender as? ModelFieldType {
                let vc = segue.destination as! EditItemVC
                vc.labelText = field.localized
                vc.itemText =  self.selectedCompany?.stringValueFor(field: field)
                vc.delegate = self
                
            }
        }
    }

    // MARK: - TextFieldTableViewCellDelegate
    
    func field(field: ModelFieldType, changedValueTo value: String) {
        self.selectedCompany?.setValue(value: value, forField: field)
        self.tableView?.reloadData()
    }
    
    func fieldDidBeginEditing(field: ModelFieldType) {

    }

    
    // MARK: protocol methods
    
    func pickHandler(_ item: String) {
        // on return from pickList view
        self.textEditHandler(item)
    }
    
    func textEditHandler(_ itemText: String) {
        // on return full-text edit view
        self.selectedCompany?.setValue(itemText, forKey: self.currentKey)
        self.tableView?.reloadData()
    }
    
    // MARK: segment actions
    
    @IBAction func segmentAction(sender: Any?) {
        let index = (sender as! UISegmentedControl).selectedSegmentIndex
    }
}
