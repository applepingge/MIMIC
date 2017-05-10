(******************************************************************************)
(*  © Université Lille 1 (2014-2017)                                          *)
(*                                                                            *)
(*  This software is a computer program whose purpose is to run a minimal,    *)
(*  hypervisor relying on proven properties such as memory isolation.         *)
(*                                                                            *)
(*  This software is governed by the CeCILL license under French law and      *)
(*  abiding by the rules of distribution of free software.  You can  use,     *)
(*  modify and/ or redistribute the software under the terms of the CeCILL    *)
(*  license as circulated by CEA, CNRS and INRIA at the following URL         *)
(*  "http://www.cecill.info".                                                 *)
(*                                                                            *)
(*  As a counterpart to the access to the source code and  rights to copy,    *)
(*  modify and redistribute granted by the license, users are provided only   *)
(*  with a limited warranty  and the software's author,  the holder of the    *)
(*  economic rights,  and the successive licensors  have only  limited        *)
(*  liability.                                                                *)
(*                                                                            *)
(*  In this respect, the user's attention is drawn to the risks associated    *)
(*  with loading,  using,  modifying and/or developing or reproducing the     *)
(*  software by the user in light of its specific status of free software,    *)
(*  that may mean  that it is complicated to manipulate,  and  that  also     *)
(*  therefore means  that it is reserved for developers  and  experienced     *)
(*  professionals having in-depth computer knowledge. Users are therefore     *)
(*  encouraged to load and test the software's suitability as regards their   *)
(*  requirements in conditions enabling the security of their systems and/or  *)
(*  data to be ensured and,  more generally, to use and operate it in the     *)
(*  same conditions as regards security.                                      *)
(*                                                                            *)
(*  The fact that you are presently reading this means that you have had      *)
(*  knowledge of the CeCILL license and that you accept its terms.            *)
(******************************************************************************)

Require Import List Arith NPeano Coq.Logic.JMeq Coq.Logic.Classical_Prop.
Import List.ListNotations .
Require Import Lib StateMonad HMonad MMU Alloc_invariants
 Properties LibOs PageTableManager MemoryManager MMU_invariant.
Require Import Coq.Structures.OrderedTypeEx.

Set Printing Projections.
(** * Read a value at a given physical address *)
Definition read_phy_addr (phy_addr : nat) := 
  perform s := get in 
               if lt_dec phy_addr  (length s.(data))  
               then ret (inl (List.nth phy_addr s.(data) 0))
               else ret (inr tt).

Lemma read_phy_addr_wp (phys_addr : nat) (P : nat+unit -> state -> Prop) :
  {{ fun s => phys_addr < length s.(data) /\ 
 P (inl (List.nth phys_addr s.(data) 0)) s \/ phys_addr >= length s.(data)  /\ P (inr tt) s}} 
read_phy_addr phys_addr {{ P }}.
Proof.
unfold read_phy_addr.
eapply bind_wp.
intros s. 

instantiate (1 := fun s' s =>s = s' /\ (phys_addr < length s.(data) /\ 
 P (inl (List.nth phys_addr s.(data) 0)) s \/ phys_addr >= length s.(data)  /\ P (inr tt) s)).
   simpl. 
case_eq (lt_dec phys_addr (length (data s))).
 + intros.
   eapply weaken.
   eapply ret_wp.
   intros.
   simpl.
   destruct H0. 
   subst. 
   intuition.
   contradict H1.
   intuition.
 + intros. 
   eapply weaken.
   apply ret_wp.
   intros.
   destruct H0.
   subst. 
   intuition.
   contradict H1.
   intuition.
 + eapply weaken.
   eapply get_wp.
   intros.
   simpl.
   destruct H. 
   intuition.
   intuition.
Qed.




Definition read ( Vaddr : nat):  M (nat+unit):= 

perform Paddr := translate Vaddr in 
match Paddr with 
|inl paddr => read_phy_addr paddr
|inr faultpage => ret (inr tt)
|inr noaccess => ret (inr tt)
end.
 




(** * assignment of the register with a value *)

Definition assign (v : nat) : M unit :=
  modify (fun s => {|
    process_list := s.(process_list);
    current_process := s.(current_process);
    cr3 := s.(cr3);
    intr_table := s.(intr_table);
    interruptions := s.(interruptions);
    kernel_mode := s.(kernel_mode);
    pc := s.(pc);
    code := s.(code);
    stack := s.(stack);
    register := v;
    first_free_page := s.(first_free_page);
    data := s.(data)    
  |}
).

Lemma assign_wp (v : nat) (P : unit -> state -> Prop) :
  {{ fun s => P tt {|
      process_list := s.(process_list);
      current_process := s.(current_process);
      cr3 := s.(cr3);
      intr_table := s.(intr_table);
      interruptions := s.(interruptions);
      kernel_mode := s.(kernel_mode);
      pc := s.(pc);
      code := s.(code);
      stack := s.(stack);
      register := v;
      first_free_page := s.(first_free_page);
      data := s.(data)    
  |}
}} assign v {{ P }}.
Proof.
apply modify_wp.
Qed.





(** * put in the regester the value at the physical address .
  *)

Definition load (Vaddr : nat) : M unit :=
perform value := read Vaddr in 
match value with 
|inl v =>  assign v
|inr _ => assign 0 
end.

Definition write_aux (val Paddr: nat) := 
let page := getBase Paddr offset_nb_bits in 
let index := getOffset Paddr offset_nb_bits in  
 modify (fun s =>  {|
    process_list := s.(process_list);
    current_process := s.(current_process);
    cr3 := s.(cr3);
    intr_table := s.(intr_table);
    interruptions := s.(interruptions);
    kernel_mode := s.(kernel_mode);
    pc := s.(pc);
    code := s.(code);
    stack := s.(stack);
    register := s.(register);
    first_free_page := s.(first_free_page);
    data := firstn (page * page_size) s.(data) ++
             update_sublist index val
               (sublist (page * page_size) page_size s.(data)) ++
             skipn (page * page_size + nb_pte) s.(data)   
|}).
Lemma write_aux_wp (val Paddr: nat) (P : unit-> state-> Prop) :
let page := getBase Paddr offset_nb_bits in 
let index := getOffset Paddr offset_nb_bits in  
{{fun s => P tt {|
    process_list := s.(process_list);
    current_process := s.(current_process);
    cr3 := s.(cr3);
    intr_table := s.(intr_table);
    interruptions := s.(interruptions);
    kernel_mode := s.(kernel_mode);
    pc := s.(pc);
    code := s.(code);
    stack := s.(stack);
    register := s.(register);
    first_free_page := s.(first_free_page);
    data := firstn (page * page_size) s.(data) ++
             update_sublist index val
               (sublist (page * page_size) page_size s.(data)) ++
             skipn (page * page_size + nb_pte) s.(data) |}
}}
write_aux val Paddr {{ P }}.
Proof.
simpl.
apply modify_wp.
Qed.


Definition write (val Vaddr : nat) := 
perform Paddr := translate Vaddr in 
match Paddr with 
|inl paddr => write_aux val paddr
|inr _ => ret tt
end.

